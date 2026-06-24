// AC3ConverterCore.swift
//
// Pure AudioToolbox path: NO AVPlayer, NO AVFoundation playback. You demux the
// AC-3 / E-AC-3 companion stream yourself, hand each syncframe (access unit) to
// this class, and get back interleaved Float PCM. Apple's OS codec does the
// decode (kAudioFormatAC3 / kAudioFormatEnhancedAC3) — your code never runs the
// Dolby algorithm. Route the PCM anywhere: a ring buffer, an AudioUnit, your
// own output, CoreAudio HAL, etc.
//
// Demux ≠ decode: pulling AC-3 packets out of MKV/M2TS is container parsing and
// is fine under "no decode in my code". The decode happens inside CoreAudio.
//
// IMPORTANT availability note: the AC-3/E-AC-3 *decoder* component must be
// present on the device. It is on macOS; on iOS/tvOS verify with
// AudioDecoderProbe.swift (look for an 'adec' component with subtype 'ac-3' /
// 'ec-3'). If absent on your min-deployment device, this path can't decode
// there and you'd fall back to remux+AVPlayer.

import AudioToolbox

public final class AC3ConverterCore {
    public enum Codec { case ac3, eac3 }

    private var converter: AudioConverterRef?
    private let channels: UInt32
    public let sampleRate: Double

    // Stable storage for the single packet handed to the input callback. The
    // callback runs synchronously inside AudioConverterFillComplexBuffer, but we
    // keep heap-stable pointers so there's no lifetime ambiguity.
    private var pktBuffer: UnsafeMutableRawPointer?
    private var pktSize: Int = 0
    private let pktDescPtr = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
    private var pktAvailable = false

    public init?(codec: Codec, sampleRate: Double = 48_000, channels: UInt32 = 6) {
        self.channels = channels
        self.sampleRate = sampleRate

        var inFmt = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: codec == .ac3 ? kAudioFormatAC3 : kAudioFormatEnhancedAC3,
            mFormatFlags: 0,
            mBytesPerPacket: 0,        // compressed: variable
            mFramesPerPacket: 1536,    // AC-3 / E-AC-3 syncframe = 1536 samples
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0)

        var outFmt = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * channels,   // interleaved Float32
            mFramesPerPacket: 1,
            mBytesPerFrame: 4 * channels,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0)

        let status = AudioConverterNew(&inFmt, &outFmt, &converter)
        guard status == noErr, converter != nil else { return nil }
    }

    deinit {
        if let c = converter { AudioConverterDispose(c) }
        if let b = pktBuffer { free(b) }
        pktDescPtr.deallocate()
    }

    /// Decode ONE AC-3/E-AC-3 access unit to interleaved Float PCM.
    /// Returns nil on error or if nothing was produced.
    public func decode(packet: Data, maxFrames: UInt32 = 1536) -> [Float]? {
        guard let converter = converter else { return nil }

        // Stage the packet into a heap-stable buffer for the callback.
        if let b = pktBuffer { free(b) }
        pktBuffer = malloc(packet.count)
        guard let pktBuffer = pktBuffer else { return nil }
        pktSize = packet.count
        packet.withUnsafeBytes { raw in
            if let base = raw.baseAddress { memcpy(pktBuffer, base, packet.count) }
        }
        pktDescPtr.pointee = AudioStreamPacketDescription(
            mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))
        pktAvailable = true

        var out = [Float](repeating: 0, count: Int(maxFrames) * Int(channels))
        var ioFrames = maxFrames
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = out.withUnsafeMutableBytes { outRaw -> OSStatus in
            var abl = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: channels,
                    mDataByteSize: UInt32(outRaw.count),
                    mData: outRaw.baseAddress))
            return AudioConverterFillComplexBuffer(converter, Self.inputProc, selfPtr, &ioFrames, &abl, nil)
        }

        guard status == noErr, ioFrames > 0 else { return nil }
        return Array(out.prefix(Int(ioFrames) * Int(channels)))
    }

    /// C input callback: feed exactly one staged packet, then signal EOF (0 pkts).
    private static let inputProc: AudioConverterComplexInputDataProc = {
        (_, ioNumPackets, ioData, outDescs, userData) in
        let me = Unmanaged<AC3ConverterCore>.fromOpaque(userData!).takeUnretainedValue()
        guard me.pktAvailable, let buf = me.pktBuffer else {
            ioNumPackets.pointee = 0      // no more input -> converter returns
            return noErr
        }
        ioNumPackets.pointee = 1
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mData = buf
        ioData.pointee.mBuffers.mDataByteSize = UInt32(me.pktSize)
        ioData.pointee.mBuffers.mNumberChannels = me.channels
        outDescs?.pointee = me.pktDescPtr
        me.pktAvailable = false
        return noErr
    }
}

// AC3DecodePipeline.swift
//
// The glue between "I have demuxed AC-3/E-AC-3 packets" and "sound comes out",
// with NO AVPlayer and NO AVFoundation. Flow:
//
//   AC3PacketSource (your demuxer)  ->  AC3ConverterCore (Apple's codec)
//        -> PCMRingBuffer  ->  output AudioUnit render callback -> speakers
//
// Your demuxer (libavformat, your own MKV/M2TS parser, etc.) only produces
// AC-3/E-AC-3 access units; it never decodes. CoreAudio decodes. This file is
// pure AudioToolbox / AudioUnit.
//
// Threading note: decode runs on a feeder thread; the AudioUnit render callback
// runs on the realtime audio thread. They meet at PCMRingBuffer, a simple
// single-producer/single-consumer ring. For production, replace the index
// updates with atomics (e.g. stdatomic) — flagged inline. This is a working
// scaffold, not a hardened RT-audio buffer.

import AudioToolbox
import Foundation

// MARK: - Packet source your demuxer conforms to

public protocol AC3PacketSource: AnyObject {
    /// Return the next AC-3/E-AC-3 access unit, or nil at end of stream.
    func nextPacket() -> Data?
}

// MARK: - Simple SPSC float ring buffer

public final class PCMRingBuffer {
    private var storage: [Float]
    private let capacity: Int
    private var writeIndex = 0      // producer (feeder thread)
    private var readIndex = 0       // consumer (audio thread)
    private let lock = NSLock()     // scaffold-grade; swap for atomics in prod

    public init(capacity: Int) {
        self.capacity = capacity
        self.storage = [Float](repeating: 0, count: capacity)
    }

    public func write(_ samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        for s in samples {
            let next = (writeIndex + 1) % capacity
            if next == readIndex { break } // full: drop (or block in prod)
            storage[writeIndex] = s
            writeIndex = next
        }
    }

    /// Fill `out` with up to `count` samples; zero-pad underflow. Returns filled.
    public func read(into out: UnsafeMutablePointer<Float>, count: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        var i = 0
        while i < count && readIndex != writeIndex {
            out[i] = storage[readIndex]
            readIndex = (readIndex + 1) % capacity
            i += 1
        }
        while i < count { out[i] = 0; i += 1 } // underflow -> silence
        return i
    }
}

// MARK: - Output AudioUnit (pure AudioToolbox; no AVFoundation)

public final class AC3DecodePipeline {
    private let decoder: AC3ConverterCore
    private let ring: PCMRingBuffer
    private let channels: UInt32
    private let sampleRate: Double
    private weak var source: AC3PacketSource?

    private var outputUnit: AudioUnit?
    private var feederThread: Thread?
    private var running = false

    public init?(codec: AC3ConverterCore.Codec,
                 source: AC3PacketSource,
                 sampleRate: Double = 48_000,
                 channels: UInt32 = 6) {
        guard let dec = AC3ConverterCore(codec: codec, sampleRate: sampleRate, channels: channels) else {
            return nil
        }
        self.decoder = dec
        self.source = source
        self.sampleRate = sampleRate
        self.channels = channels
        // ~0.5s of interleaved float headroom.
        self.ring = PCMRingBuffer(capacity: Int(sampleRate) * Int(channels) / 2)
    }

    public func start() throws {
        try setupOutputUnit()
        running = true
        let t = Thread { [weak self] in self?.feedLoop() }
        t.name = "ac3.decode.feeder"
        t.start()
        feederThread = t
        if let u = outputUnit { try check(AudioOutputUnitStart(u), "AudioOutputUnitStart") }
    }

    public func stop() {
        running = false
        if let u = outputUnit {
            AudioOutputUnitStop(u)
            AudioUnitUninitialize(u)
            AudioComponentInstanceDispose(u)
            outputUnit = nil
        }
    }

    // Decode loop: pull packets, decode to PCM, push into the ring.
    private func feedLoop() {
        while running, let pkt = source?.nextPacket() {
            if let pcm = decoder.decode(packet: pkt) {
                ring.write(pcm)
            }
        }
    }

    private func setupOutputUnit() throws {
        #if os(macOS)
        let subType = kAudioUnitSubType_DefaultOutput
        #else
        let subType = kAudioUnitSubType_RemoteIO   // iOS / tvOS
        #endif

        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: subType,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)

        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "AC3DecodePipeline", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No output AudioUnit"])
        }
        var unit: AudioUnit?
        try check(AudioComponentInstanceNew(comp, &unit), "AudioComponentInstanceNew")
        guard let outputUnit = unit else {
            throw NSError(domain: "AC3DecodePipeline", code: -2)
        }
        self.outputUnit = outputUnit

        // Interleaved Float32 PCM matching the decoder output.
        var streamFmt = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * channels, mFramesPerPacket: 1,
            mBytesPerFrame: 4 * channels, mChannelsPerFrame: channels,
            mBitsPerChannel: 32, mReserved: 0)
        try check(AudioUnitSetProperty(outputUnit, kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Input, 0, &streamFmt,
                                       UInt32(MemoryLayout<AudioStreamBasicDescription>.size)),
                  "set StreamFormat")

        // Render callback pulls from the ring.
        var cb = AURenderCallbackStruct(
            inputProc: Self.renderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try check(AudioUnitSetProperty(outputUnit, kAudioUnitProperty_SetRenderCallback,
                                       kAudioUnitScope_Input, 0, &cb,
                                       UInt32(MemoryLayout<AURenderCallbackStruct>.size)),
                  "set RenderCallback")

        try check(AudioUnitInitialize(outputUnit), "AudioUnitInitialize")
    }

    // Realtime render callback: copy interleaved float from the ring.
    private static let renderCallback: AURenderCallback = {
        (refCon, _, _, _, inNumberFrames, ioData) in
        let me = Unmanaged<AC3DecodePipeline>.fromOpaque(refCon).takeUnretainedValue()
        guard let abl = ioData else { return noErr }
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        let needed = Int(inNumberFrames) * Int(me.channels)
        if let buf = buffers.first, let data = buf.mData {
            _ = me.ring.read(into: data.assumingMemoryBound(to: Float.self), count: needed)
        }
        return noErr
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        if status != noErr {
            throw NSError(domain: "AC3DecodePipeline", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "\(what) failed: \(status)"])
        }
    }
}

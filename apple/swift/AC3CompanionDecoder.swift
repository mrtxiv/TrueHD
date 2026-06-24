// AC3CompanionDecoder.swift
//
// The "no decode by your app" path: play the AC-3 / E-AC-3 companion track that
// ships alongside a Dolby TrueHD stream, using APPLE'S OWN decoder. Your code
// never runs the MLP/Dolby decode algorithm — CoreAudio does it. Works on
// iOS, macOS, and tvOS. Trade-off: this is the lossy 5.1 companion, not the
// lossless TrueHD. (See ../../FINDINGS.md for why lossless can't meet the
// no-decode + no-hardware constraints.)
//
// NO AVPlayer, NO HLS, NO AVPlayerItem track selection here — by design.
// You DEMUX the AC-3/E-AC-3 access units yourself (MKV/M2TS/TS), then feed them
// to `AppleAC3Decoder`, which uses AVAudioConverter (Apple's codec) to turn them
// into PCM you schedule on an AVAudioEngine. The lowest-level, fully no-AVPlayer
// playback chain is `AC3DecodePipeline` (pure AudioToolbox); this AVAudioEngine
// variant is a simpler alternative when you don't need raw AudioUnit control.

import AVFoundation
import AudioToolbox

// MARK: - AVAudioConverter decode for custom demuxers (MKV/M2TS access units)

public final class AppleAC3Decoder {
    public enum Codec { case ac3, eac3 }

    private let inputFormat: AVAudioFormat
    public let pcmFormat: AVAudioFormat
    private let converter: AVAudioConverter

    /// - Parameters:
    ///   - codec: .ac3 or .eac3 (the companion track's codec)
    ///   - sampleRate: usually 48000
    ///   - channels: 6 for 5.1 (the typical companion layout)
    public init?(codec: Codec, sampleRate: Double = 48_000, channels: UInt32 = 6) {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: codec == .ac3 ? kAudioFormatAC3 : kAudioFormatEnhancedAC3,
            mFormatFlags: 0,
            mBytesPerPacket: 0,        // variable (compressed)
            mFramesPerPacket: 1536,    // AC-3/E-AC-3: 1536 samples per syncframe
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0)

        guard let inFmt = AVAudioFormat(streamDescription: &asbd),
              let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: AVAudioChannelCount(channels),
                                         interleaved: false),
              let conv = AVAudioConverter(from: inFmt, to: outFmt)
        else { return nil }

        self.inputFormat = inFmt
        self.pcmFormat = outFmt
        self.converter = conv
    }

    /// Decode ONE AC-3/E-AC-3 access unit (one syncframe) to PCM using Apple's
    /// codec. Returns nil on error. `nil` is also returned if the decoder needs
    /// more data; feed the next access unit.
    public func decode(accessUnit: Data) -> AVAudioPCMBuffer? {
        let compressed = AVAudioCompressedBuffer(
            format: inputFormat,
            packetCapacity: 1,
            maximumPacketSize: accessUnit.count
        )
        compressed.byteLength = UInt32(accessUnit.count)
        compressed.packetCount = 1
        accessUnit.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                compressed.data.copyMemory(from: base, byteCount: accessUnit.count)
            }
        }
        if let pd = compressed.packetDescriptions {
            pd.pointee = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(accessUnit.count)
            )
        }

        guard let out = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 1536) else {
            return nil
        }

        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return compressed
        }

        if status == .error || error != nil { return nil }
        return out
    }
}

// MARK: - Minimal playback wiring (all three platforms)

public final class AC3CompanionPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let decoder: AppleAC3Decoder

    public init?(codec: AppleAC3Decoder.Codec) {
        guard let d = AppleAC3Decoder(codec: codec) else { return nil }
        self.decoder = d
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: d.pcmFormat)
    }

    public func start() throws {
        try engine.start()
        node.play()
    }

    /// Feed a demuxed AC-3/E-AC-3 access unit; Apple decodes, we schedule PCM.
    public func enqueue(accessUnit: Data) {
        guard let pcm = decoder.decode(accessUnit: accessUnit) else { return }
        node.scheduleBuffer(pcm, completionHandler: nil)
    }
}

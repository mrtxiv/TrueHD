// AC3CompanionDecoder.swift
//
// The "no decode by your app" path: play the AC-3 / E-AC-3 companion track that
// ships alongside a Dolby TrueHD stream, using APPLE'S OWN decoder. Your code
// never runs the MLP/Dolby decode algorithm — CoreAudio does it. Works on
// iOS, macOS, and tvOS. Trade-off: this is the lossy 5.1 companion, not the
// lossless TrueHD. (See ../../FINDINGS.md for why lossless can't meet the
// no-decode + no-hardware constraints.)
//
// Two ways to use Apple's decoder, depending on where your audio comes from:
//
//   A. AVFoundation-native container (MP4/MOV/HLS): just SELECT the AC-3 track
//      with AVPlayer media selection. Apple decodes + plays it. Zero decode
//      code, most robust, all platforms. -> `selectAC3Track(in:)`.
//      NOTE: this variant uses AVPlayer. If your product forbids AVPlayer/HLS,
//      do NOT use path A — use the pure-AudioToolbox `AC3DecodePipeline` (no
//      AVPlayer, no HLS) instead. Path A is kept only for AVFoundation-native apps.
//
//   B. Your own demuxer (MKV/M2TS): feed AC-3/E-AC-3 access units to
//      `AppleAC3Decoder`, which uses AVAudioConverter (Apple's codec) to turn
//      them into PCM you can schedule on an AVAudioEngine. -> `AppleAC3Decoder`.

import AVFoundation
import AudioToolbox

// MARK: - A. AVPlayer track selection (native containers, truly zero decode code)

public enum AC3TrackSelector {
    /// FourCCs Apple's decoder handles: 'ac-3' (AC-3) and 'ec-3' (E-AC-3 / DD+).
    public static let decodableFourCCs: Set<String> = ["ac-3", "ec-3"]

    /// Select the AC-3/E-AC-3 audio track (the TrueHD companion) so AVPlayer
    /// decodes it with Apple's codec. Returns true if such a track was selected.
    public static func selectAC3Track(in playerItem: AVPlayerItem) async -> Bool {
        guard let asset = playerItem.asset as? AVURLAsset,
              let group = try? await asset.loadMediaSelectionGroup(for: .audible)
        else { return false }

        for option in group.options {
            // Prefer options whose format is AC-3 / E-AC-3.
            if let fmt = option.mediaType == .audio ? option : nil,
               optionIsAC3(fmt) {
                playerItem.select(option, in: group)
                return true
            }
        }
        return false
    }

    private static func optionIsAC3(_ option: AVMediaSelectionOption) -> Bool {
        // AVMediaSelectionOption doesn't expose the codec directly; fall back to
        // common-metadata/format hints. For precise matching, inspect the
        // AVAssetTrack format descriptions (see `isAC3` below).
        let s = option.displayName.lowercased()
        return s.contains("ac3") || s.contains("ac-3") || s.contains("dolby digital")
            || s.contains("dd+") || s.contains("eac3") || s.contains("e-ac-3")
    }

    /// Precise codec check on an AVAssetTrack's format descriptions.
    public static func isAC3(_ track: AVAssetTrack) async -> Bool {
        guard let descs = try? await track.load(.formatDescriptions) else { return false }
        for d in descs {
            let mst = CMFormatDescriptionGetMediaSubType(d)
            let fourCC = fourCCString(mst)
            if decodableFourCCs.contains(fourCC) { return true }
        }
        return false
    }

    static func fourCCString(_ code: FourCharCode) -> String {
        let b = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
                 UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(bytes: b, encoding: .ascii) ?? ""
    }
}

// MARK: - B. AVAudioConverter decode for custom demuxers (MKV/M2TS access units)

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

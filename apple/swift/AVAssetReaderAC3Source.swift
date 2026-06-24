// AVAssetReaderAC3Source.swift
//
// Apple-native demuxer for the AC-3 path: pulls raw AC-3 / E-AC-3 access units
// out of an MP4/MOV container using AVAssetReader, with NO third-party code and
// NO LGPL. AVAssetReader only *reads* (demuxes) the compressed samples — it does
// not decode them — so this complies with "we never decode". The packets it
// returns go straight into AC3ConverterCore (where Apple's codec decodes them).
//
// Scope: works for containers AVFoundation can open (MP4 / MOV / m4v / fragmented
// MP4). For MKV / M2TS, AVFoundation can't open the container — use a third-party
// demuxer (e.g. libavformat for DEMUX only; note libavformat is LGPL) and adapt
// its packet output to the same AC3PacketSource protocol.

import AVFoundation
import AudioToolbox

public final class AVAssetReaderAC3Source: AC3PacketSource {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput

    /// Codec discovered on the selected track, so the pipeline can pick .ac3/.eac3.
    public let codec: AC3ConverterCore.Codec

    public init?(url: URL) {
        let asset = AVURLAsset(url: url)
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }

        // Find an audio track whose stored format is AC-3 ('ac-3') or E-AC-3 ('ec-3').
        // NOTE: `tracks(withMediaType:)` is synchronous; on modern SDKs prefer
        // `await asset.loadTracks(withMediaType: .audio)`.
        var found: (AVAssetTrack, AC3ConverterCore.Codec)?
        for track in asset.tracks(withMediaType: .audio) {
            for desc in track.formatDescriptions {
                let d = desc as! CMFormatDescription
                switch CMFormatDescriptionGetMediaSubType(d) {
                case kAudioFormatAC3:          found = (track, .ac3)
                case kAudioFormatEnhancedAC3:  found = (track, .eac3)
                default:                       continue
                }
                break
            }
            if found != nil { break }
        }
        guard let (track, codec) = found else { return nil }
        self.codec = codec

        // outputSettings: nil  ->  deliver samples in their STORED (compressed)
        // format. This is the key: we get raw AC-3 packets, not decoded PCM.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        self.reader = reader
        self.output = output
    }

    /// Next AC-3/E-AC-3 access unit, or nil at end of stream.
    ///
    /// Caveat: a single CMSampleBuffer usually holds one AC-3 syncframe, but the
    /// format permits several. If you hit a stream that packs multiple frames per
    /// sample buffer, split using CMSampleBufferGetNumSamples + the per-sample
    /// size array before feeding AC3ConverterCore one syncframe at a time.
    public func nextPacket() -> Data? {
        guard reader.status == .reading,
              let sb = output.copyNextSampleBuffer(),
              let block = CMSampleBufferGetDataBuffer(sb) else {
            return nil
        }
        var length = 0
        var ptr: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            block, atOffset: 0, lengthAtOffsetOut: nil,
            totalLengthOut: &length, dataPointerOut: &ptr)
        guard status == kCMBlockBufferNoErr, let p = ptr, length > 0 else { return nil }
        return Data(bytes: p, count: length)
    }
}

// Convenience: build the whole AC-3 playback pipeline from a single MP4/MOV URL,
// fully Apple-native (no third-party demuxer, no LGPL), app decodes nothing.
public extension AC3DecodePipeline {
    static func makeFromMP4(url: URL, sampleRate: Double = 48_000, channels: UInt32 = 6) -> AC3DecodePipeline? {
        guard let source = AVAssetReaderAC3Source(url: url) else { return nil }
        return AC3DecodePipeline(codec: source.codec, source: source,
                                 sampleRate: sampleRate, channels: channels)
    }
}

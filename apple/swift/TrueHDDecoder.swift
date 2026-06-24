// TrueHDDecoder.swift
// Swift wrapper over the Apache-2.0 Rust decode core. Feed it TrueHD access
// units; get interleaved Float PCM you can schedule on an AVAudioEngine.
//
// Bridging: add `apple/include/truehd_decoder.h` to your bridging header (or a
// module map) and link the static lib / xcframework built from `decoder-core`.

import AVFoundation

public final class TrueHDDecoder {
    private let handle: UnsafeMutableRawPointer

    public init?() {
        guard let h = truehd_decoder_new() else { return nil }
        self.handle = h
    }

    deinit { truehd_decoder_free(handle) }

    public struct PCM {
        public let samples: [Float]   // interleaved
        public let channels: Int
    }

    public enum DecodeResult {
        case pcm(PCM)
        case needMoreData
        case error(Int32)
    }

    /// Decode one TrueHD access unit (channel bed).
    public func decode(accessUnit: Data, maxFrames: Int = 8192) -> DecodeResult {
        var out = [Float](repeating: 0, count: maxFrames * 16) // up to 16ch headroom
        var frames: size_t = 0
        var channels: UInt32 = 0

        let status = accessUnit.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int32 in
            out.withUnsafeMutableBufferPointer { (ob: inout UnsafeMutableBufferPointer<Float>) -> Int32 in
                truehd_decoder_decode(
                    handle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    accessUnit.count,
                    ob.baseAddress,
                    size_t(maxFrames),
                    &frames,
                    &channels
                )
            }
        }

        switch status {
        case THD_OK.rawValue:
            let count = Int(frames) * Int(channels)
            return .pcm(PCM(samples: Array(out.prefix(count)), channels: Int(channels)))
        case THD_NEED_MORE_DATA.rawValue:
            return .needMoreData
        default:
            return .error(status)
        }
    }

    /// Convenience: wrap interleaved Float PCM into an AVAudioPCMBuffer for
    /// scheduling on an AVAudioPlayerNode (works on iOS/macOS/tvOS).
    public static func makeBuffer(from pcm: PCM, sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(pcm.channels),
            interleaved: true
        ) else { return nil }

        let frames = pcm.samples.count / max(pcm.channels, 1)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        buf.frameLength = AVAudioFrameCount(frames)
        if let dst = buf.floatChannelData {
            pcm.samples.withUnsafeBufferPointer { src in
                dst[0].update(from: src.baseAddress!, count: pcm.samples.count)
            }
        }
        return buf
    }
}

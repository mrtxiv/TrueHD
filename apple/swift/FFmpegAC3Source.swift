// FFmpegAC3Source.swift
//
// Bridges the libavformat demuxer (ffmpeg_ac3_demux.c) into the Swift pipeline.
// FFmpeg DEMUXES (no decode); Apple's AudioToolbox decodes downstream. No AVPlayer.
//
// Setup: expose `apple/include/ffmpeg_ac3_demux.h` to Swift via a bridging header
// or module map, compile `apple/src/ffmpeg_ac3_demux.c`, and link libavformat /
// libavcodec / libavutil (dynamic; LGPL). The demuxer opens MKV/M2TS/TS/MP4 —
// anything FFmpeg can open.

import Foundation

public final class FFmpegAC3Source: AC3PacketSource {
    private var handle: OpaquePointer?
    public let codec: AC3ConverterCore.Codec
    public let channels: UInt32
    public let sampleRate: Double

    public init?(url: URL) {
        var c = AC3DEMUX_NONE
        var ch: Int32 = 0
        var sr: Int32 = 0
        guard let h = url.path.withCString({ ac3demux_open($0, &c, &ch, &sr) }) else {
            return nil
        }
        self.handle = h
        self.codec = (c == AC3DEMUX_EAC3) ? .eac3 : .ac3
        self.channels = UInt32(ch > 0 ? ch : 6)
        self.sampleRate = Double(sr > 0 ? sr : 48_000)
    }

    deinit { if let h = handle { ac3demux_close(h) } }

    public func nextPacket() -> Data? {
        guard let h = handle else { return nil }
        var data: UnsafePointer<UInt8>?
        var size: Int32 = 0
        let r = ac3demux_next(h, &data, &size)
        guard r == 1, let d = data, size > 0 else { return nil }
        return Data(bytes: d, count: Int(size))   // copy; pointer invalid after next call
    }
}

// One-call setup from any FFmpeg-openable container (MKV/M2TS/TS/MP4...).
// FFmpeg demuxes, Apple decodes, output goes to an AudioUnit. No AVPlayer.
public extension AC3DecodePipeline {
    static func makeWithFFmpeg(url: URL) -> AC3DecodePipeline? {
        guard let source = FFmpegAC3Source(url: url) else { return nil }
        return AC3DecodePipeline(codec: source.codec,
                                 source: source,
                                 sampleRate: source.sampleRate,
                                 channels: source.channels)
    }
}

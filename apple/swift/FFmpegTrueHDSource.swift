// FFmpegTrueHDSource.swift  (tvOS 26+)
//
// Bridges the libavformat TrueHD demuxer (thddemux_* in ffmpeg_ac3_demux.c) to
// the passthrough renderer. FFmpeg DEMUXES only (no decode); the untouched
// TrueHD bitstream is handed to AVSampleBufferAudioRenderer for OS passthrough
// to an AVR. No AVPlayer.

#if os(tvOS)
import Foundation
import CoreMedia

public final class FFmpegTrueHDSource: TrueHDPacketSource {
    private var handle: OpaquePointer?
    public let channels: UInt32
    public let sampleRate: Double

    public init?(url: URL) {
        var ch: Int32 = 0
        var sr: Int32 = 0
        guard let h = url.path.withCString({ thddemux_open($0, &ch, &sr) }) else {
            return nil
        }
        self.handle = h
        self.channels = UInt32(ch > 0 ? ch : 8)
        self.sampleRate = Double(sr > 0 ? sr : 48_000)
    }

    deinit { if let h = handle { thddemux_close(h) } }

    public func nextPacket() -> (data: Data, pts: CMTime)? {
        guard let h = handle else { return nil }
        var data: UnsafePointer<UInt8>?
        var size: Int32 = 0
        var pts: Double = 0
        let r = thddemux_next(h, &data, &size, &pts)
        guard r == 1, let d = data, size > 0 else { return nil }
        let bytes = Data(bytes: d, count: Int(size))   // copy before next call
        let time = pts.isNaN ? CMTime.invalid
                             : CMTime(seconds: pts, preferredTimescale: 90_000)
        return (bytes, time)
    }
}
#endif

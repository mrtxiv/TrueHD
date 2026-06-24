// TrueHDCoreAC3Source.swift
//
// Extract the interleaved AC-3 "core" from a Dolby TrueHD (MLP) elementary
// stream, WITHOUT decoding TrueHD and WITHOUT any GPL/LGPL dependency.
//
// ── THE PROBLEM (why scanning track formats for kAudioFormatAC3 finds nothing)
//   A Blu-ray "Dolby TrueHD" track is a *combo* elementary stream: independent
//   TrueHD (MLP) frames and AC-3 frames are interleaved frame-by-frame in ONE
//   stream, sharing no data. A container demuxer (libavformat, AVAssetReader)
//   therefore reports a single `truehd` stream; there is no separate `ac-3`
//   stream to select, so matching kAudioFormatAC3 against the track formats
//   returns nothing. (eac3to surfaces it as "embedded: AC3"; the command
//   `eac3to in.thd out.ac3 -core` extracts it.)
//
// ── THE SOLUTION (this file)
//   The AC-3 core exists precisely so legacy decoders can read it, so it is
//   *standard* AC-3: every core frame begins with the AC-3 syncword 0x0B77 and
//   a standard ATSC A/52 header. We scan the elementary stream for valid AC-3
//   syncframes, validate each header, lock onto the core's constant bitrate,
//   and emit each frame as a clean AC-3 access unit. The MLP bytes between the
//   AC-3 frames are skipped — never decoded. Apple's OS codec (AC3ConverterCore)
//   then decodes the AC-3, exactly as in the existing AC-3-companion path.
//
// ── WHY THIS RESPECTS YOUR CONSTRAINTS
//   * No TrueHD decode by you. We read frame *headers/lengths* and copy bytes.
//     There is zero inverse-MLP math here; this is demuxing — the same kind of
//     work as splitting packets out of a container. The only decode is Apple's,
//     on the AC-3.
//   * No GPL/LGPL. The AC-3 syncframe layout is the public ATSC A/52 standard.
//     This parser is written from that spec — not copied from FFmpeg/eac3to —
//     and pulls in no third-party demuxer.
//
// ── SCOPE / CAVEATS (see apple/AC3_CORE_EXTRACTION.md and apple/CHOSEN_PATH.md)
//   * The interleaved core exists only in *unaltered* Blu-ray sources: a raw
//     `.thd` elementary stream, or the audio PID payload demuxed from an `.m2ts`.
//     Remuxing to MKV splits the core into a separate track or drops it (MKV
//     cannot carry a combo track), so MKV TrueHD usually has NO interleaved
//     core. When none is found, `init?` returns nil — fall back to the lossless
//     decoder-core/ path for that title.
//   * The core is lossy AC-3 (<= 640 kbps, typically 5.1) — the accepted
//     trade-off for "Apple decodes, your app does not".
//   * Input must be a TrueHD *elementary stream*. For `.m2ts`, PID-demux first
//     (container parsing, also not decoding) to obtain the elementary stream.

import Foundation
import AudioToolbox

/// An `AC3PacketSource` that de-interleaves the AC-3 core out of a Dolby TrueHD
/// combo elementary stream. Plugs directly into `AC3DecodePipeline` /
/// `AC3ConverterCore` — Apple's codec does the only decoding.
public final class TrueHDCoreAC3Source: AC3PacketSource {

    // MARK: Public — discovered from the first valid core frame.

    public let codec: AC3ConverterCore.Codec = .ac3
    /// Sample rate of the core. The Blu-ray AC-3 core is always 48 kHz.
    public let sampleRate: Double
    /// Channel count from the core's `acmod` + `lfeon` (e.g. 6 for 3/2+LFE).
    public let channelCount: UInt32
    /// Nominal core bitrate in kbps (e.g. 640). The core is constant-bitrate.
    public let bitrateKbps: Int

    // MARK: Scan state.

    private let data: Data
    private var cursor: Int
    /// CBR lock: every core frame shares this `frmsizecod`. Used to reject stray
    /// 0x0B77 byte patterns that occur inside MLP data.
    private let lockedFrmSizeCod: Int

    /// ATSC A/52 Table 5.18 nominal bitrate (kbps), indexed by `frmsizecod >> 1`.
    private static let bitrateTab: [Int] =
        [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512, 576, 640]

    /// Channels per `acmod` (front+surround), before adding LFE. ATSC A/52 5.4.2.2.
    private static let channelsPerAcmod: [Int] = [2, 1, 2, 3, 3, 4, 4, 5]

    // MARK: Init.

    /// Open a TrueHD elementary stream and confirm it carries an AC-3 core.
    /// Returns nil if no valid AC-3 core frame is found (TrueHD-only / MKV-stripped).
    public init?(data: Data) {
        // Find the first valid AC-3 syncframe: (a) confirms a core is present,
        // (b) captures sample rate / channels / bitrate, (c) locks the CBR size.
        // Done before assigning any stored property so the nil-return path is
        // valid on every Swift version.
        guard let first = TrueHDCoreAC3Source.findFrame(in: data, from: 0, locked: nil) else {
            return nil
        }
        self.data = data
        self.sampleRate = first.sampleRate
        self.channelCount = first.channels
        self.bitrateKbps = first.bitrateKbps
        self.lockedFrmSizeCod = first.frmsizecod
        self.cursor = first.offset   // first frame is returned by the first nextPacket()
    }

    /// Convenience: memory-mapped (`.mappedIfSafe`) so multi-GB `.thd` files are
    /// not loaded into RAM. The bytes are paged in on demand during scanning.
    public convenience init?(url: URL) {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        self.init(data: d)
    }

    // MARK: AC3PacketSource.

    /// The next AC-3 access unit (one 1536-sample syncframe), or nil at end.
    public func nextPacket() -> Data? {
        guard let f = TrueHDCoreAC3Source.findFrame(in: data, from: cursor, locked: lockedFrmSizeCod) else {
            return nil
        }
        cursor = f.offset + f.size
        return data.subdata(in: f.offset ..< f.offset + f.size)
    }

    // MARK: - AC-3 syncframe parse (clean-room from ATSC A/52)

    private struct Frame {
        let offset: Int
        let size: Int
        let frmsizecod: Int
        let channels: UInt32
        let sampleRate: Double
        let bitrateKbps: Int
    }

    /// Scan forward from `from` for the next valid AC-3 core syncframe. When
    /// `locked` is non-nil, only frames with that `frmsizecod` (same CBR) are
    /// accepted, which rejects 0x0B77 patterns that appear inside MLP frames.
    private static func findFrame(in data: Data, from: Int, locked: Int?) -> Frame? {
        let n = data.count
        if from < 0 || from + 8 > n { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Frame? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var i = from
            while i + 8 <= n {
                if base[i] == 0x0B && base[i + 1] == 0x77,
                   let f = parse(base, at: i, limit: n),
                   locked == nil || f.frmsizecod == locked {
                    return f
                }
                i += 1
            }
            return nil
        }
    }

    /// Parse + validate one AC-3 syncframe at `off`. Returns nil unless it is a
    /// sane 48 kHz AC-3 header whose frame fits within `limit`.
    private static func parse(_ p: UnsafePointer<UInt8>, at off: Int, limit: Int) -> Frame? {
        // syncinfo: byte[off+4] = fscod (2 bits) | frmsizecod (6 bits).
        let b4 = Int(p[off + 4])
        let fscod = (b4 >> 6) & 0x3
        let frmsizecod = b4 & 0x3F
        // The Blu-ray core is 48 kHz; requiring it is correct AND a strong
        // false-positive filter against random 0x0B77 bytes in MLP data.
        guard fscod == 0 else { return nil }
        let bri = frmsizecod >> 1
        guard bri < bitrateTab.count else { return nil }      // frmsizecod 0..37 are valid

        // bsi: byte[off+5] = bsid (5 bits) | bsmod (3 bits). AC-3 (incl. the
        // alternate bit-stream syntax) is bsid <= 10; 11..16 is E-AC-3, which is
        // not the legacy core and uses a different frame-size field — reject it.
        let bsid = (Int(p[off + 5]) >> 3) & 0x1F
        guard bsid <= 10 else { return nil }

        let kbps = bitrateTab[bri]
        let size = kbps * 4   // 48 kHz: frame bytes = bitrate_kbps * 4 (A/52 Table 5.18)
        guard off + size <= limit else { return nil }

        // Channels: acmod (+ conditional mix-level fields) then lfeon.
        // acmod begins at byte[off+6], bit 7 (MSB-first).
        var br = BitReader(p, startBit: (off + 6) * 8)
        let acmod = br.read(3)
        if (acmod & 0x1) != 0 && acmod != 1 { _ = br.read(2) }  // cmixlev  (three front channels)
        if (acmod & 0x4) != 0 { _ = br.read(2) }                // surmixlev (surround present)
        if acmod == 2 { _ = br.read(2) }                        // dsurmod  (2/0 stereo)
        let lfeon = br.read(1)
        let channels = UInt32(channelsPerAcmod[acmod] + (lfeon == 1 ? 1 : 0))

        return Frame(offset: off, size: size, frmsizecod: frmsizecod,
                     channels: channels, sampleRate: 48_000, bitrateKbps: kbps)
    }
}

/// Minimal MSB-first bit reader over a raw byte pointer. Used only to walk the
/// few conditional AC-3 bsi fields between `acmod` and `lfeon`.
private struct BitReader {
    private let p: UnsafePointer<UInt8>
    private var bit: Int
    init(_ p: UnsafePointer<UInt8>, startBit: Int) { self.p = p; self.bit = startBit }
    mutating func read(_ count: Int) -> Int {
        var v = 0
        for _ in 0 ..< count {
            let b = (Int(p[bit >> 3]) >> (7 - (bit & 7))) & 1
            v = (v << 1) | b
            bit += 1
        }
        return v
    }
}

// One-call wiring: a combo TrueHD elementary stream (.thd) -> AC-3 core ->
// Apple's OS decoder -> speakers, with no AVPlayer and no decode by your app.
public extension AC3DecodePipeline {
    /// Build the no-AVPlayer AC-3 playback pipeline straight from a TrueHD combo
    /// elementary stream by de-interleaving its AC-3 core. Returns nil when the
    /// stream carries no core (use the decoder-core/ lossless path for those).
    static func makeFromTrueHDCore(url: URL) -> AC3DecodePipeline? {
        guard let source = TrueHDCoreAC3Source(url: url) else { return nil }
        return AC3DecodePipeline(codec: source.codec, source: source,
                                 sampleRate: source.sampleRate, channels: source.channelCount)
    }
}

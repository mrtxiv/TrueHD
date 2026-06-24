# Extracting the interleaved AC-3 core from a TrueHD combo stream

This is the answer to the wall you hit: *a Blu-ray "Dolby TrueHD" track is a
combo elementary stream — independent TrueHD (MLP) and AC-3 frames interleaved
frame-by-frame in one stream, sharing no data — so a demuxer reports a single
`truehd` stream and matching `kAudioFormatAC3` against the track formats finds
nothing.* There is no separate AC-3 **stream** to select. But there is a
separate AC-3 **frame sequence** sitting inside that one stream, and you can pull
it out **without decoding TrueHD and without a GPL/LGPL dependency.**

Code: [`swift/TrueHDCoreAC3Source.swift`](swift/TrueHDCoreAC3Source.swift).

## Why this is demuxing, not decoding (and why it's license-clean)

The AC-3 core exists for exactly one reason: legacy receivers that cannot decode
TrueHD must still get sound. So the core is **standard AC-3** — every frame
starts with the AC-3 syncword `0x0B77` and a standard ATSC A/52 header. Getting
it out is:

1. **Scan** the elementary stream for `0x0B77`.
2. **Validate** the A/52 header (48 kHz `fscod`, sane `frmsizecod`, AC-3-range
   `bsid`) and compute the frame length from the header.
3. **Lock** onto the core's constant bitrate, so stray `0x0B77` byte patterns
   inside MLP data are rejected.
4. **Emit** each validated frame as a clean AC-3 access unit; **skip** the MLP
   bytes in between.

Step 1–4 read frame *headers and lengths* and copy bytes. There is **zero
inverse-MLP math** — this is the same kind of work as splitting packets out of a
container. The only decode is Apple's, on the AC-3 (`AC3ConverterCore` →
`kAudioFormatAC3`), exactly as in the existing AC-3-companion path. And because
the AC-3 syncframe layout is the **public ATSC A/52 standard**, the parser is
written from that spec — not copied from FFmpeg or eac3to — and pulls in no
third-party demuxer. So:

| Your constraint | This path |
| --- | --- |
| You don't decode TrueHD | ✅ de-interleave only; no inverse-MLP |
| No GPL/LGPL | ✅ clean-room A/52 parser, no third-party demuxer |
| Apple does the decode | ✅ `kAudioFormatAC3` via AudioToolbox |
| All three platforms | ✅ AC-3 decoder is on iOS/macOS/tvOS |
| No external hardware | ✅ decode + PCM on-device |
| Lossless | ❌ the core is lossy AC-3 — the accepted trade-off |

This is, in effect, what `eac3to in.thd out.ac3 -core` does, reimplemented as a
small permissive `AC3PacketSource` you can ship.

## Usage

```swift
// Combo TrueHD elementary stream (.thd) -> AC-3 core -> Apple's decoder -> out.
// No AVPlayer, no decode by your app, no GPL/LGPL.
if let pipeline = AC3DecodePipeline.makeFromTrueHDCore(url: thdURL) {
    try pipeline.start()
} else {
    // No interleaved core in this stream (TrueHD-only / MKV-stripped):
    // fall back to the lossless decoder-core/ path for this title.
}
```

Or drive the source directly (e.g. to inspect what was found):

```swift
guard let core = TrueHDCoreAC3Source(url: thdURL) else { /* no core */ }
print(core.bitrateKbps, core.channelCount)   // e.g. 640, 6  (640 kbps 5.1)
let pipeline = AC3DecodePipeline(codec: core.codec, source: core,
                                 sampleRate: core.sampleRate, channels: core.channelCount)
```

## The one hard limit: the core has to actually be there

The interleaved core exists **only in unaltered Blu-ray sources** — a raw `.thd`
elementary stream, or the audio PID payload demuxed from an `.m2ts`. The moment
TrueHD is remuxed into **MKV**, the core is split into a *separate* AC-3 track or
dropped entirely, because the MKV container cannot carry a combo track (one codec
per track). So a TrueHD track pulled from an MKV usually has **no interleaved
core** to find — `TrueHDCoreAC3Source.init?` returns `nil` for those, and you
fall back to [`../decoder-core/`](../decoder-core) (lossless, all platforms).

Decision table for a given source:

| Source | Where the AC-3 is | What to use |
| --- | --- | --- |
| Unaltered Blu-ray `.m2ts` / `.thd` | Interleaved in the `truehd` stream | **`TrueHDCoreAC3Source`** (this file) |
| MP4/MOV with a separate AC-3/E-AC-3 track | Its own track | `AVAssetReaderAC3Source` |
| MKV/M2TS with a separate AC-3 track | Its own track | a stream-iterating demuxer (e.g. `ffmpeg_ac3_demux`, demux-only) |
| TrueHD-only (no core anywhere) | — | `decoder-core/` (lossless bundled decoder) |

## Input scope and hardening notes

- **Input is a TrueHD elementary stream.** For `.m2ts`, PID-demux first to get
  the elementary stream (container parsing — also not decoding). A small
  clean-room TS PID extractor can be added in front of this if you want a
  no-libav `.m2ts` → core path end to end.
- **Robustness.** Validation is header sanity (`fscod`/`frmsizecod`/`bsid`) plus
  a constant-bitrate lock, which is what makes the syncword scan reliable against
  false positives in MLP data. For belt-and-suspenders you can add A/52 `crc1`
  verification over each candidate frame.
- **Large files.** `init?(url:)` memory-maps with `.mappedIfSafe`, so multi-GB
  `.thd` files are paged in during scanning rather than loaded into RAM.
- **Segment splices.** If you concatenate per-segment `.m2ts` payloads yourself,
  de-duplicate identical frames at the splice boundaries (the same care
  `domyd/mlp` takes for TrueHD frames).

## Sources

- Combo-stream structure (interleaved, independent frames):
  [Dolby TrueHD — Wikipedia](https://en.wikipedia.org/wiki/Dolby_TrueHD),
  [doom9: TrueHD+AC3 is alternating frames](https://forum.doom9.org/archive/index.php/t-155499.html)
- Core extraction precedent: `eac3to in.thd out.ac3 -core`
  ([VideoHelp](https://forum.videohelp.com/threads/380429-(eac3to)-extracting-AC3-from-TrueHD))
- MKV cannot carry the combo (core is split/dropped on remux):
  [makemkv: Retain TrueHD 'AC3 Core'](https://forum.makemkv.com/forum/viewtopic.php?t=1568),
  [doom9: Mux TrueHD to MKV retaining AC3 core](https://forum.doom9.org/archive/index.php/t-153118.html)
- AC-3 syncframe layout (public standard): ATSC A/52 — syncword `0x0B77`,
  `fscod`/`frmsizecod` in syncinfo, `bsid`/`acmod` in bsi.

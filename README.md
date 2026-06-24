# TrueHD on Apple platforms (iOS / macOS / tvOS)

A worked-out answer — with code — to: *"how do I play Dolby TrueHD audio in a
media player on Apple platforms?"*

## The short version

There is **no** configuration that plays **lossless TrueHD** while
simultaneously requiring **no decoder in your app**, **no external hardware**,
and **all three platforms**. That combination is empty, because Apple ships no
TrueHD decoder, so *something* must decode and there's nothing left to do it.
Full reasoning with sources: [`FINDINGS.md`](FINDINGS.md).

So you pick which constraint gives. This repo implements the two most useful
choices and a router to switch between them:

| You accept... | You get | Code |
| --- | --- | --- |
| A bundled (non-GPL) decoder runs | **Lossless bed**, all platforms, on-device, no license | [`decoder-core/`](decoder-core) + [`apple/BUILD.md`](apple/BUILD.md) |
| Lossy instead of lossless | **AC-3/E-AC-3** via Apple's own codec — no decoder you wrote | [`apple/swift/`](apple/swift) |

## File map

- [`VERIFICATION.md`](VERIFICATION.md) — **read this first.** Every load-bearing
  claim in this repo, its primary source, and a true/false verdict (audited
  2026-06-24). Records what was corrected, including citations that did not hold up.
- [`FINDINGS.md`](FINDINGS.md) — the full feasibility analysis + sources.
- [`AudioDecoderProbe.swift`](AudioDecoderProbe.swift) — **run this first** on
  your target device. Enumerates OS audio codecs; confirms no TrueHD decoder
  exists and whether the AC-3/E-AC-3 decoder is present.
- `apple/CHOSEN_PATH.md` — the AC-3 companion decision + caveats.
- `apple/swift/AC3ConverterCore.swift` — **pure AudioToolbox**: AC-3/E-AC-3
  packet → PCM via Apple's codec. No AVPlayer, no AVFoundation.
- `apple/swift/AC3DecodePipeline.swift` — demuxer → `AC3ConverterCore` → ring
  buffer → output AudioUnit. The full no-AVPlayer playback chain.
- `apple/swift/AC3CompanionDecoder.swift` — AVFoundation variants
  (`AVAudioConverter` decoder + optional AVPlayer track selection).
- `apple/swift/TrueHDPlaybackRouter.swift` — pure policy function: choose
  lossless-bed vs AC-3-companion per source, with honest UI disclosure strings.
- `decoder-core/` — Apache-2.0 `truehd` (NOT GPL/LGPL) Rust core behind a C ABI,
  for the opt-in lossless path. Build per `apple/BUILD.md`.

## Usage: no-AVPlayer AC-3/E-AC-3 playback

```swift
// 1. Your demuxer (MKV/M2TS parser, libavformat, etc.) emits AC-3 packets.
//    Demuxing is container parsing, NOT decoding — fine under "no decode in my code".
final class MyDemuxer: AC3PacketSource {
    func nextPacket() -> Data? { /* return next AC-3/E-AC-3 access unit, or nil */ }
}

// 2. Wire it up. Apple's codec decodes; output goes to an AudioUnit. No AVPlayer.
let source = MyDemuxer()
guard let pipeline = AC3DecodePipeline(codec: .eac3, source: source,
                                       sampleRate: 48_000, channels: 6) else { return }
try pipeline.start()
// ... later ...
pipeline.stop()
```

## Before you ship — read these caveats honestly

1. **Verify the decoder exists on-device.** Run `AudioDecoderProbe.swift`; look
   for an `'adec'` component with subtype `'ac-3'` / `'ec-3'`. Present on macOS;
   confirm on your minimum iOS/tvOS targets. If absent, fall back to remux+AVPlayer.
2. **A companion track must exist.** TrueHD titles usually carry a separate
   AC-3/E-AC-3 track or an embedded AC-3 core; your demuxer must surface it. A
   TrueHD-only title has nothing for this path to play — use `decoder-core/`.
3. **The ring buffer in `AC3DecodePipeline` is a scaffold.** Swap its `NSLock`
   for atomics before relying on it in a real-time audio context.
4. **Lossless ≠ free of patents.** The foundational MLP lossless patents expired
   ~2017, but get counsel before commercial ship; Atmos *objects* remain patented
   (in force well into the 2030s–2040s) and are intentionally out of scope here.

## What this repo does NOT do

- It does not render Dolby **Atmos objects** (live patents; needs a Dolby license).
- It does not claim a private Apple TrueHD decoder exists (it doesn't —
  `AudioDecoderProbe.swift` lets you confirm).
- It does not bundle any GPL/LGPL decoder.

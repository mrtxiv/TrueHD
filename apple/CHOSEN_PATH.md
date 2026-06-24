# Chosen path: AC-3 companion track via Apple's own decoder

This is the configuration selected for the player: **no decode by your app, no
external hardware, all three platforms, no license, App-Store-shippable.** The
deliberately accepted trade-off is **lossy** (the AC-3/E-AC-3 5.1 companion),
not the lossless TrueHD. Per `../FINDINGS.md`, lossless cannot coexist with
"nothing in my app decodes" + "no external hardware," because Apple ships no
TrueHD decoder — so something else must decode, and here that something is the
AC-3 companion handled by Apple's OS codec.

## Requirement scorecard for this path

| Req | Status |
| --- | --- |
| #1 lossless | ✗ accepted trade-off — lossy AC-3/E-AC-3 5.1 |
| #2 iOS/macOS/tvOS | ✓ Apple's AC-3/E-AC-3 decoder is on all three |
| #3 no decode in your code | ✓ CoreAudio decodes; you only demux/select |
| #4 legal, no license, shippable | ✓ AC-3 patents expired (2017); public API; no Dolby fee |
| #5 no external hardware | ✓ decode + PCM on-device |
| #6 no GPL/LGPL | ✓ no third-party decoder at all |

## How it works

No AVPlayer, no HLS. You demux the AC-3/E-AC-3 access units yourself (demux-only,
no decode) and let Apple's codec decode them. Two output graphs are provided:

- **Pure AudioToolbox (`AC3DecodePipeline`):** demuxer → `AC3ConverterCore`
  (`AudioConverter`) → ring buffer → output `AudioUnit`. No AVFoundation at all.
- **AVAudioEngine (`AC3CompanionDecoder`):** feed access units to
  `AppleAC3Decoder` (wraps `AVAudioConverter` → Apple's codec) and schedule the
  resulting `AVAudioPCMBuffer` on an `AVAudioEngine` via `AC3CompanionPlayer`.

Demuxers: `AVAssetReaderAC3Source` (Apple-native, MP4/MOV) or `FFmpegAC3Source`
(MKV/M2TS via libavformat, demux-only). Neither uses AVPlayer or HLS.

## Honest caveats — verify before shipping

1. **A companion track must exist.** Most Blu-ray/UHD TrueHD tracks ship a
   separate Dolby Digital (AC-3) or DD+ (E-AC-3) track, OR the TrueHD carries an
   embedded AC-3 core. Your demuxer must surface it. If a title has *only*
   TrueHD with no AC-3 anywhere, this path has nothing to play — fall back to
   the bundled-decoder path (`decoder-core/`) for that title.
2. **Raw-packet AC-3 decode availability.** Raw `AVAudioConverter` / `AudioConverter`
   AC-3/E-AC-3 decode is well-supported on macOS and current iOS/tvOS, but
   validate on your minimum-deployment devices with `AudioDecoderProbe.swift`. If
   a device refuses raw-packet AC-3 decode, this no-AVPlayer/no-HLS path cannot
   serve it — present an "unsupported on this device" state (an AVPlayer
   track-selection fallback is intentionally out of scope).
3. **Channel layout.** The companion is typically 5.1. Set `channels`/layout to
   match the actual track; don't assume 6.

## If you later want lossless too

Keep this AC-3 path as the universal default, and offer the Apache-2.0
`truehdd` core (`decoder-core/`, see `BUILD.md`) as an opt-in "lossless" mode
for users who accept that a bundled (non-GPL, not-your-code) decoder runs. That
gives a clean two-tier player: lossless when available, AC-3 companion always.

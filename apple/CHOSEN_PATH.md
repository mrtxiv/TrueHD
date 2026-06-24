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

Code: `apple/swift/AC3CompanionDecoder.swift`. Two entry points:

- **Native containers (MP4/MOV/HLS):** `AC3TrackSelector.selectAC3Track(in:)`
  picks the AC-3/E-AC-3 audio option and lets `AVPlayer` decode + play it.
  This is the most robust form — literally zero decode code.
- **Custom demux (MKV/M2TS):** feed AC-3/E-AC-3 access units to
  `AppleAC3Decoder` (wraps `AVAudioConverter` → Apple's codec) and schedule the
  resulting `AVAudioPCMBuffer` on an `AVAudioEngine` via `AC3CompanionPlayer`.

## Honest caveats — verify before shipping

1. **A companion AC-3 must exist — both shapes are now handled.** TrueHD tracks
   ship AC-3 either as a *separate* Dolby Digital (AC-3) / DD+ (E-AC-3) track, or
   as an AC-3 *core interleaved inside the TrueHD stream* (unaltered Blu-ray).
   The separate track is surfaced by `AVAssetReaderAC3Source` (MP4) or a
   stream-iterating demuxer (MKV/M2TS); the interleaved core — where a demuxer
   shows only `truehd` and `kAudioFormatAC3` matches nothing — is de-interleaved
   by `TrueHDCoreAC3Source` (`AC3_CORE_EXTRACTION.md`), without decoding TrueHD
   and without GPL/LGPL. Only a title that is *truly* TrueHD-only (no core
   anywhere, common after MKV remux) has nothing for this path; fall back to the
   bundled-decoder path (`decoder-core/`) there.
2. **iOS AC-3-via-AVAudioConverter availability.** AC-3/E-AC-3 decode is
   reliable through AVPlayer/HLS on all platforms; raw `AVAudioConverter` AC-3
   decode is well-supported on macOS and current iOS/tvOS, but validate on your
   minimum-deployment devices. If a device refuses raw-packet AC-3 decode, use
   the AVPlayer track-selection route instead.
3. **Channel layout.** The companion is typically 5.1. Set `channels`/layout to
   match the actual track; don't assume 6.

## If you later want lossless too

Keep this AC-3 path as the universal default, and offer the Apache-2.0
`truehdd` core (`decoder-core/`, see `BUILD.md`) as an opt-in "lossless" mode
for users who accept that a bundled (non-GPL, not-your-code) decoder runs. That
gives a clean two-tier player: lossless when available, AC-3 companion always.

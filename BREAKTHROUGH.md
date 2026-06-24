# Breakthrough: no-AVPlayer, no-self-decode, LOSSLESS TrueHD on tvOS 26

Deeper GitHub digging (SDK diffs + reading two real 2026 players) found a path
that satisfies almost every constraint you set — the app decodes nothing,
bundles no decoder, uses NO AVPlayer, and the audio stays lossless TrueHD. The
one price (unavoidable) is an external AVR and tvOS-only.

## The new facts (tvOS 26 / Xcode 26)

1. **CORRECTION (June 2026): `AudioCodecContentSource` is NOT the bitstream
   switch.** This doc originally claimed `kAudioCodecContentSource_Passthrough` /
   `_ApplePassthrough` (and `AVAudioContentSource.passthrough`) tells the OS to
   pass a bitstream through. That was wrong — a name collision. That enum is the
   `contentSource` value for **AVAudioConverter's Dynamic Range Compression
   (DRC)** behavior; `.passthrough` means "apply DRC without tailoring it to a
   content type." It has nothing to do with HDMI bitstream-out. There is, as of
   now, **no confirmed public developer API** to enable tvOS 26 HDMI passthrough
   from a hand-built renderer — Swiftfin #1641 and KSPlayer #862 are still OPEN
   feature requests with no working sample, and the only shipping passthrough so
   far (Infuse/Plex) is via the AVPlayer/AVPlayerItem family.
2. **`AVSampleBufferAudioRenderer` accepts COMPRESSED buffers.** Apple's docs:
   it "is an object used to decompress audio and play compressed or uncompressed
   audio." So you can enqueue compressed TrueHD `CMSampleBuffer`s to it WITHOUT
   AVPlayer, paired with an `AVSampleBufferRenderSynchronizer`.
3. **⚠️ RETRACTED citations.** Earlier versions of this file cited specific
   Swift files/quotes from "Moonfin-Core (`AppleTvVideoChannel.swift`)" and
   "Rivulet (`FFmpegAudioDecoder.swift`, `DirectPlayPipeline.swift`)" as proof
   that real players do this. Fact-check (see `FACT_CHECK.md`) could **not verify
   them**: Moonfin is Flutter+MPVKit (its iOS/tvOS playback is MPV, not the cited
   Swift); the real `Rivulet` is an MPV app without those files. Treat those
   quotes as **unverified / likely fabricated**. (An earlier note cited Moonfin
   "Smart-TV #179" as evidence — withdrawn: that repo is Tizen/webOS, not Apple TV.)
   The one REAL corroboration — **AetherEngine** — does the opposite: it
   stream-copies **E-AC-3+JOC** for Atmos passthrough and **transcodes** TrueHD
   to E-AC-3/FLAC rather than passing it through. Even Dolby's own `daaplay`
   decodes to PCM and explicitly does NOT use AVSampleBufferAudioRenderer.

## What this gives you (and the one thing it doesn't)

| Your constraint | This path |
| --- | --- |
| App never decodes | ✅ OS/AVR handles the bitstream |
| No bundled decoder | ✅ none needed for the passthrough path |
| No AVPlayer | ✅ uses `AVSampleBufferAudioRenderer` directly |
| Lossless TrueHD (incl. Atmos) | ✅ untouched bitstream → AVR decodes losslessly |
| All three platforms | ❌ **tvOS only** (HDMI bitstream out) |
| No external hardware | ❌ **needs an AVR/soundbar** over HDMI |

So this is NOT "Apple decodes TrueHD on-device" — that still doesn't exist. It
is the closest real thing: **the OS routes the lossless TrueHD bitstream to an
external decoder, driven by AudioToolbox/AVSampleBufferAudioRenderer with no
AVPlayer and no decoding in your app.** The external AVR is mandatory; over
AirPlay/HomePod the compressed route is silent and you must decode to PCM.

## Implementation
See `apple/swift/TrueHDPassthroughRenderer.swift` — feeds demuxed TrueHD access
units (your FFmpeg demuxer, no decode) into `AVSampleBufferAudioRenderer` tagged
`'mlpa'`, no AVPlayer. The content-source/passthrough-enable call is marked
VERIFY against the shipping tvOS 26 SDK (no complete public example exists yet;
Swiftfin #1641 and KSPlayer #862 are still open feature requests).

## Honest status of the original dream
Lossless TrueHD + no self-decode + no AVPlayer + external AVR on tvOS is
**plausible but UNPROVEN**. The wall is unchanged: nothing on-device decodes
TrueHD, so an AVR is mandatory and it's tvOS-only. What this doc can no longer
claim is that the *no-AVPlayer* enable path is "buildable today" — the API to
flip bitstream passthrough on a hand-built AVSampleBufferAudioRenderer is not
public/confirmed (see correction above). The renderer in
`apple/swift/TrueHDPassthroughRenderer.swift` is the best-guess scaffold; its
`configurePassthrough()` is deliberately a no-op + HDMI sanity check, not a
working switch. The one path proven to ship passthrough so far is via AVPlayer —
which your constraints exclude. **The dependable, real-today path remains the
AC-3 demux fallback (no AVPlayer, no HLS): `AC3DecodePipeline`.**

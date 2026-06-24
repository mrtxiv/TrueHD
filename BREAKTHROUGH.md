# Breakthrough: no-AVPlayer, no-self-decode, LOSSLESS TrueHD on tvOS 26

Deeper GitHub digging (SDK diffs + reading two real 2026 players) found a path
that satisfies almost every constraint you set — the app decodes nothing,
bundles no decoder, uses NO AVPlayer, and the audio stays lossless TrueHD. The
one price (unavoidable) is an external AVR and tvOS-only.

## The new facts (tvOS 26 / Xcode 26)

1. **Passthrough is a low-level AudioToolbox capability, not just an AVPlayer
   feature.** New enum `AudioCodecContentSource` adds:
   - `kAudioCodecContentSource_Passthrough`
   - `kAudioCodecContentSource_ApplePassthrough`
   (source: tvOS 26 AudioToolbox header diff, dotnet/macios wiki). This means the
   OS can be told "do not decode — pass this bitstream through."
2. **`AVSampleBufferAudioRenderer` accepts COMPRESSED buffers.** Apple's docs:
   it "is an object used to decompress audio and play compressed or uncompressed
   audio." So you can enqueue compressed TrueHD `CMSampleBuffer`s to it WITHOUT
   AVPlayer, paired with an `AVSampleBufferRenderSynchronizer`.
3. **Real players already do bitstream passthrough this way (2026):**
   - **Moonfin-Core** (`AppleTvVideoChannel.swift`): for `truehd`/`mlp` with
     `atmosPassthrough && isAtmosFamily && channels != 2`, it sets
     `configurePreferredBackendForNextPlayback(.native)` — routing TrueHD to the
     OS for passthrough, falling back to mpv (bundled decode) otherwise.
   - **Rivulet** (`FFmpegAudioDecoder.swift`, `DirectPlayPipeline.swift`):
     uses `AVSampleBufferAudioRenderer` compressed passthrough, and documents the
     key gotcha — *"compressed passthrough via AVSampleBufferAudioRenderer is
     silent on AirPlay; all audio must be decoded to PCM for AirPlay output."*
     For AirPlay it does TrueHD→PCM→EAC3→HomePods instead.

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
Lossless TrueHD + no self-decode + no AVPlayer is now reachable — but only with
an external AVR on tvOS. Remove the AVR (your #5) and it collapses back to the
empty set, because nothing on-device decodes TrueHD. That wall is unchanged; the
breakthrough is that the no-decode/no-AVPlayer *bitstream-out* path is real and
buildable on tvOS 26.

# Status of the "no-AVPlayer, no-self-decode, lossless TrueHD" idea on tvOS 26

> **Honesty note (2026-06):** an earlier version of this file called this a
> confirmed "breakthrough" and cited shipping players as proof. A deep
> fact-check (see [`VERIFICATION.md`](VERIFICATION.md)) showed that was
> overstated. This file now states only what is verifiable. The short version:
> **the no-AVPlayer lossless-TrueHD-passthrough path is NOT proven to work and
> may not be possible today.** What *is* real is described below, separated from
> what is not.

## What is actually verified (with sources)

1. **tvOS 26 adds audio passthrough.** Confirmed by Apple's tvOS 26 release notes
   and multiple outlets ([FlatpanelsHD](https://www.flatpanelshd.com/news.php?subaction=showfull&id=1749568309),
   [AppleInsider](https://forums.appleinsider.com/discussion/240595/passthrough-audio-is-finally-on-the-way-to-apple-tv-iphone-and-more)).
   It routes a bitstream to an HDMI-connected AV receiver, which decodes.
2. **The passthrough constants are real.** `kAudioCodecContentSource_Passthrough = 42`
   and `kAudioCodecContentSource_ApplePassthrough = 10` exist in the real
   `AudioToolbox/AudioCodec.h` shipped in the iOS/tvOS/macOS 26 SDKs (verified in
   [xybp888/iOS-SDKs](https://github.com/xybp888/iOS-SDKs), WebKit SDKDB, objc2).
   The header describes `_Passthrough` as *"Passthrough content (use only if
   source information is not available)"* — it is a **codec content-source hint**,
   not a documented "send this bitstream untouched to HDMI" switch.
3. **`AVAudioContentSource` is a real AVFoundation enum**, new in 26.0 (dotnet/macios
   bindings, MobiVM/robovm `#since 26.0`).
4. **`AVSampleBufferAudioRenderer` accepts compressed buffers** — Apple's docs say
   it "is an object used to decompress audio and play compressed or uncompressed
   audio." Note the operative word is **decompress** (decode), not passthrough.

## What is NOT verified — and why this is not yet a usable path

- **No shipping code anywhere does lossless-TrueHD compressed passthrough via
  `AVSampleBufferAudioRenderer` with no AVPlayer.** A GitHub-wide code search
  found none (see [`VERIFICATION.md`](VERIFICATION.md)). The real players that
  were checked do the opposite for TrueHD:
  - **Rivulet** (`l984-451/Rivulet`) wraps **AAC/AC-3/E-AC-3** as `CMSampleBuffer`
    and hands them to `AVSampleBufferAudioRenderer`, but for **TrueHD/DTS it
    FFmpeg-decodes to PCM**. Its own code: *"Audio transcode needed for
    DTS/TrueHD (AVPlayer can't decode them)."* So Rivulet is **evidence against**
    TrueHD passthrough through this renderer, not for it.
  - **Moonfin-Core** (`Moonfin-Client/Moonfin-Core`) routes the Atmos family
    (incl. `truehd`/`mlp`) to a `.native` backend via
    `configurePreferredBackendForNextPlayback(.native)` — but that backend is a
    **custom `AudioRenderer` that calls `decodePacket(...)`**, i.e. it appears to
    *decode*, not bitstream-passthrough. It is **not** a confirmed
    AVSampleBufferAudioRenderer-passthrough example.
  - **Sodalite / AetherEngine** (`superuser404notfound/*`) **transcode** TrueHD to
    an EAC3 (or optional FLAC) bridge — not lossless TrueHD passthrough.
- **`AVSampleBufferAudioRenderer` decompresses (decodes).** With no OS TrueHD
  decoder, enqueuing `'mlpa'` buffers is expected to **fail**, not pass through.
- **The enable call is unknown.** `TrueHDPassthroughRenderer.configurePassthrough()`
  in this repo is an empty stub because there is no demonstrated API to make that
  renderer bitstream TrueHD. It is unverified and may not exist.
- **Real-world status:** early tvOS 26 betas reportedly expose **no toggle to
  enable passthrough**, and observers note macOS does not passthrough TrueHD/DTS
  and doubt tvOS will. Whether **lossless** TrueHD (vs. DD/DD+/DTS) ever passes
  through is **unconfirmed**.
- **The feature requests are CLOSED, not active proof.** [Swiftfin #1641](https://github.com/jellyfin/Swiftfin/issues/1641)
  is **closed as "not planned"**; [KSPlayer #862](https://github.com/kingslay/KSPlayer/issues/862)
  is **closed**. Neither has a working implementation.

## A constraint conflict you should know about

The press signals that the passthrough adoption path is **AVPlayer-based**
(Infuse/Plex/VLC "adopting the new API"). If lossless TrueHD passthrough only
ever ships through AVPlayer, then **"lossless TrueHD passthrough AND no AVPlayer"
is currently an empty set.** For **AC-3/E-AC-3**, compressed →
`AVSampleBufferAudioRenderer` (no AVPlayer) is demonstrated (Rivulet). For
**lossless TrueHD**, it is not.

## Honest bottom line

The realistic, *today* options under "no decode by my app, no Dolby license"
remain:

| Goal | Real status |
| --- | --- |
| Lossless TrueHD, no app decode, no AVPlayer, no HDMI AVR | **Empty set** — nothing on-device decodes TrueHD |
| Lossless TrueHD via tvOS 26 HDMI passthrough to an AVR | **Unproven**; needs an AVR; may require AVPlayer; lossless support unconfirmed in betas |
| Lossy AC-3/E-AC-3 companion via Apple's own decoder | **Works today** — all platforms, no AVPlayer, no license (see `apple/swift/AC3DecodePipeline.swift`) |
| Lossless on-device | Only by **bundling** a decoder (Apache-2.0 `truehdd`) — "your app decodes" |

The buildable, verifiable default is the **AC-3/E-AC-3 companion path**. The
tvOS 26 passthrough path is a reasonable *bet on a future capability*, but it
must be gated behind a runtime probe and labeled experimental until someone
demonstrates lossless TrueHD actually bitstreaming out. See
[`VERIFICATION.md`](VERIFICATION.md) for every claim and its source.

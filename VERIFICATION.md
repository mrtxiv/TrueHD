# VERIFICATION — every load-bearing claim, its source, and its verdict

Date of audit: **2026-06-24**. Method: each claim re-checked against a primary
source — Apple SDK headers, Apple developer docs, Wikipedia/standards pages,
vendor support pages, and **direct reads of the actual GitHub repos** cited.
Verdicts: ✅ verified true · ⚠️ true-but-needs-care · ❌ false/removed ·
❓ unverifiable (dropped or marked).

This file exists because an earlier pass on this branch asserted things that did
not hold up (a "breakthrough" that isn't proven, plus several repo citations that
could not be confirmed). Everything below is what survives scrutiny.

## A. Platform / API facts

| # | Claim | Verdict | Source |
|---|---|---|---|
| A1 | Apple ships **no** TrueHD/MLP decoder on any platform | ✅ | No `kAudioFormatMLP`/`kAudioFormatTrueHD` in any Apple SDK; CoreAudio decodes AC-3/E-AC-3/E-AC-3 JOC only |
| A2 | CoreAudio decodes AC-3, E-AC-3, E-AC-3 JOC (Atmos-in-EAC3) only | ✅ | Apple CoreAudioTypes / AudioFormatID |
| A3 | `kAudioFormatAC3`, `kAudioFormat60958AC3`, `kAudioFormatEnhancedAC3` are real | ✅ | AudioToolbox headers; used in `AC3ConverterCore.swift` / `AudioDecoderProbe.swift` |
| A4 | `'mlpa'` is the MLP/TrueHD FourCC; AC-3 frame = 1536 samples | ✅ | FFmpeg mov codec tag; AC-3 spec (6 blocks × 256) |
| A5 | tvOS 26 adds audio passthrough (bitstream to AVR) | ✅ | [FlatpanelsHD](https://www.flatpanelshd.com/news.php?subaction=showfull&id=1749568309), [AppleInsider](https://forums.appleinsider.com/discussion/240595/passthrough-audio-is-finally-on-the-way-to-apple-tv-iphone-and-more), tvOS 26 release notes |
| A6 | `kAudioCodecContentSource_Passthrough = 42`, `_ApplePassthrough = 10` exist | ✅ | Real `AudioToolbox/AudioCodec.h` in iOS/tvOS/macOS 26.0–26.5 SDK ([xybp888/iOS-SDKs](https://github.com/xybp888/iOS-SDKs), WebKit SDKDB, objc2). Header: *"Passthrough content (use only if source information is not available)"* — a codec content-source hint |
| A7 | `AVAudioContentSource` is a real AVFoundation enum, since 26.0 | ✅ | dotnet/macios bindings; MobiVM/robovm `#since 26.0`; darwodin |
| A8 | `AVSampleBufferAudioRenderer` accepts compressed buffers | ⚠️ | Apple docs: "decompress audio and play compressed or uncompressed audio" — it **decodes**; this is NOT evidence of TrueHD bitstream passthrough |
| A9 | Apple has no native DTS decoder | ✅ | Long-standing; Apple supported-formats list shows AC-3, not DTS |
| A10 | Using Apple's AC-3/E-AC-3 decoder needs **no** Dolby license from the app | ✅ | KSPlayer #875 (verbatim, see C); Apple platform license covers it |

## B. Patents & licensing

| # | Claim | Verdict | Source |
|---|---|---|---|
| B1 | AC-3 last US patent expired **March 20, 2017** | ✅ | [AVS Forum](https://www.avsforum.com/threads/dolbys-last-patent-related-to-ac-3-expired-today-3-20-17.2789001/), EFF, CNX-Software |
| B2 | E-AC-3 / MLP / TrueHD patents did **NOT** expire (only AC-3) | ✅ | Same sources explicitly exclude EAC-3/MLP/TrueHD |
| B3 | Foundational MLP lossless patents expired ~2017 | ✅ | GB2323754 (IIR lossless) lapsed Feb 2017 — Wikipedia/Grokipedia MLP |
| B4 | Atmos object (OAMD) patents still in force | ✅ (date softened) | Filings from 2010s run ~20 yrs → into 2030s–2040s. Earlier "~2046" was an **unsubstantiated specific** → softened. Durable proof: Infuse decodes only the bed, drops Atmos objects |
| B5 | `truehdd`/`truehd` crate is Apache-2.0, decodes TrueHD→PCM | ✅ | [github.com/truehdd/truehdd](https://github.com/truehdd/truehdd) (Apache-2.0; positioned for R&D, not production) |
| B6 | Infuse holds paid Dolby+DTS licenses; decodes TrueHD/DTS-HD MA → multichannel LPCM; no Atmos objects | ✅ | [Firecore support](https://support.firecore.com/hc/en-us/articles/217735707-Audio-Options-Capabilities), Firecore community |

## C. GitHub issues (existence + quotes)

| # | Claim | Verdict | Source |
|---|---|---|---|
| C1 | Swiftfin #1641 requests AVAudioContentSource.passthrough | ✅ but **CLOSED as "not planned"** | [#1641](https://github.com/jellyfin/Swiftfin/issues/1641) — earlier docs said "still open"; corrected |
| C2 | KSPlayer #862 "TvOS 26 Audio Passthrough" | ✅ but **CLOSED** | [#862](https://github.com/kingslay/KSPlayer/issues/862) — corrected from "open" |
| C3 | KSPlayer #875 quotes ("AVPlayer is the ONLY way…", "does NOT require additional licensing", "supports mp4 & hls… NOT mkv") | ✅ verbatim accurate | [#875](https://github.com/kingslay/KSPlayer/issues/875) |

## D. Cited player repos (the integrity check)

| Repo cited | Real? | What it actually does (verified) | Verdict |
|---|---|---|---|
| `superuser404notfound/AetherEngine` (+ Sodalite, AetherPlayer) | ✅ real | FFmpeg demux/decode; TrueHD **transcoded** to EAC3/FLAC bridge, not lossless passthrough | ✅ |
| `l984-451/Rivulet` | ✅ real | AC-3/E-AC-3 → `CMSampleBuffer` passthrough to `AVSampleBufferAudioRenderer`; **TrueHD/DTS FFmpeg-decoded to PCM** ("Audio transcode needed for DTS/TrueHD (AVPlayer can't decode them)" — verbatim) | ✅ (earlier framing as "TrueHD passthrough" was **backwards** → corrected) |
| `Moonfin-Client/Moonfin-Core` | ✅ real | `tvos/Runner/Playback/AppleTvVideoChannel.swift` routes Atmos family (incl. truehd/mlp) to `.native` via `configurePreferredBackendForNextPlayback(.native)` (verbatim). Native backend = custom `AudioRenderer` calling `decodePacket(...)` → **decodes**, not confirmed OS passthrough | ⚠️ (real; "routes TrueHD to OS for passthrough" was an **over-interpretation** → corrected) |
| `VortXTV/VortX` | ✅ real | **mpv-based**; mpv does spdif/bitstream passthrough to AVR (`MPVMetalViewController.swift`) | ⚠️ (real; the quoted file `AudioOutputMode.swift` and its verbatim text were **NOT found** → quote marked unverified) |
| FFmpeg `--enable-decoder=truehd` builds | ✅ real practice | Found in `abadari3/CastTV/scripts/build-ffmpeg.sh`; KSPlayer/MPVKit do likewise | ⚠️ (practice verified; exact attribution to `kingslay/FFmpegKit/BuildFFMPEG.swift` unverified → softened) |
| `Plozz` / `EngineRouting.swift` | ❓ | repo/file/quote not confirmed by repo or code search | ❌ removed |
| `Reef` / `PlaybackEngine.swift` | ❓ | no matching repo found | ❌ removed |
| `OmniPlay` | ❓ | no matching repo found | ❌ removed |
| `chenqi92/my-nas` | ❓ | not found | ❌ removed |
| `lsvr_apmp-converter`, `AmbiMux` (`.appleAV_Spatial_Offline`) | ❓ | not confirmed | ❌ removed |

## E. The central "breakthrough" claim

> **Claim (old `BREAKTHROUGH.md`):** lossless TrueHD plays with no app decode, no
> bundled decoder, **no AVPlayer**, via `AVSampleBufferAudioRenderer` compressed
> passthrough on tvOS 26 — and real 2026 players already do it.

**Verdict: ❌ not proven; reframed as unproven/experimental.** Reasons:

1. No shipping code anywhere does it (GitHub-wide search). Every verified player
   either bundles a decoder, transcodes, or FFmpeg-decodes TrueHD to PCM.
2. `AVSampleBufferAudioRenderer` *decompresses* (decodes); with no OS TrueHD
   decoder, enqueuing `'mlpa'` is expected to fail, not passthrough.
3. The enable API is an empty `// VERIFY` stub — no demonstrated mechanism.
4. Betas reportedly expose no passthrough toggle; lossless support unconfirmed;
   both tracking issues are closed.
5. Press signals the passthrough path is **AVPlayer-based** — so "lossless
   passthrough AND no AVPlayer" may be an empty set today.

**Repo decision (2026-06):** per the no-AVPlayer/no-HLS product rule, the
AVPlayer passthrough scaffold (`TrueHDPassthrough.swift`) and the AVPlayer AC-3
track-selector (`AC3TrackSelector` in `AC3CompanionDecoder.swift`) were
**removed**. Only the unproven no-AVPlayer passthrough renderer remains. Honest
consequence: **if lossless TrueHD passthrough requires AVPlayer, this repo has no
working lossless passthrough path** — only the proven lossy AC-3 companion (and
the optional bundled `truehdd` decoder for an on-device lossless bed).

## F. What remains TRUE and buildable

- **AC-3/E-AC-3 companion via Apple's own decoder** — all platforms, no AVPlayer,
  no HLS, no Dolby license, lossy 5.1. Code: `apple/swift/AC3ConverterCore.swift`
  + `AC3DecodePipeline.swift`. (Blu-ray TrueHD always carries a mandatory,
  **separate** AC-3 companion — [Wikipedia](https://en.wikipedia.org/wiki/Dolby_TrueHD).)
- **Lossless on-device** only by **bundling** Apache-2.0 `truehdd` (your app
  decodes; bed is likely patent-clear; Atmos objects out of scope).
- **tvOS 26 passthrough** — keep as an **experimental, probe-gated** path; do not
  advertise lossless TrueHD passthrough until it is demonstrated on a shipping
  build.

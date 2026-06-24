# GitHub research: player issues & discussions (TrueHD on Apple)

Searched issues/discussions across Apple-platform players, including the
Chinese-maintained **KSPlayer** (kingslay) and **NipaPlay**, plus Swiftfin,
Jellyfin, MDK, tsMuxer, mlp, HandBrake. Same conclusion as before, plus two
findings that improve the implementation.

## Finding 1 — Using Apple's decoders needs NO Dolby license for the app

From **KSPlayer #875** ("Add native Dolby Vision & Atmos via AVPlayer"):
- "AVPlayer is currently the **ONLY** way to get Dolby Atmos and Dolby Vision
  working properly on iOS/tvOS."
- "AVPlayer **does NOT require additional licensing by app devs** to play Dolby."
- "Supports mp4 & hls natively but **NOT mkv**."

Why it matters: when you route audio through Apple's own decoders (AC-3, E-AC-3,
E-AC-3 JOC/Atmos) — whether via AVPlayer or AudioToolbox — **the app needs no
Dolby license**; Apple's platform license covers it. This is exactly why the
AC-3 companion path is license-free. It does NOT extend to TrueHD, because Apple
ships no TrueHD decoder. ([KSPlayer #875](https://github.com/kingslay/KSPlayer/issues/875))

## Finding 2 — Passthrough is the only no-decode lossless route, and it's unbuilt

**Swiftfin #1641** and **KSPlayer #862** both request `AVAudioContentSource.passthrough`
(tvOS 26 / iOS 26) for lossless TrueHD. Both are **feature requests with no
working implementation** — just links to Apple's doc. tvOS 26 AudioToolbox adds
`kAudioCodecContentSource_Passthrough = 42`. Passthrough sends the bitstream to
an external AVR (external hardware decodes). ([Swiftfin #1641](https://github.com/jellyfin/Swiftfin/issues/1641),
[KSPlayer #862](https://github.com/kingslay/KSPlayer/issues/862))

## Finding 3 — Everyone who plays TrueHD *decodes it themselves*

Issues across FFmpeg/MDK/LAVFilters/Kodi show people decoding TrueHD with their
own (FFmpeg/MDK) decoders and hitting bugs ("No restart header present in
substream 0", "Stream parameters not seen"). No one uses an Apple TrueHD
decoder, because there isn't one.

## Finding 4 — The AC-3 companion: always present on Blu-ray, but mux-dependent

Important refinement for the demuxer (sources: [VideoHelp](https://forum.videohelp.com/threads/374089),
[Wikipedia: Dolby TrueHD](https://en.wikipedia.org/wiki/Dolby_TrueHD),
[BDInfo #3](https://github.com/UniqProject/BDInfo/issues/3)):

- **Every commercial Blu-ray TrueHD track is mandatorily accompanied by AC-3.**
  So a 5.1 AC-3 fallback essentially always exists in disc-sourced content.
- BUT it is **NOT a shared "core"** like DTS-HD MA. "The TrueHD bitstream has no
  data in common with the AC-3 bitstream." On Blu-ray they are **two separate
  streams interleaved within the same track**; AC-3 is an optional fallback.
- **Extraction:** "use the AC-3 frames and discard the TrueHD frames."
- **What this means for the FFmpeg demuxer:**
  - **MKV rips (most common):** eac3to/mkvtoolnix usually split them into a
    separate AC-3 track → `FFmpegAC3Source` finds `AV_CODEC_ID_AC3` → works.
  - **Raw M2TS / a single combined track:** FFmpeg may expose only the TRUEHD
    stream and not surface the interleaved AC-3 as its own stream → no AC-3
    found. For those, split the interleaved TrueHD+AC-3 frames (eac3to-style:
    keep AC-3 syncframes) before feeding the pipeline.

## Net

GitHub confirms, across English and Chinese projects: no Apple TrueHD decoder;
Apple-decoder paths are license-free for the app; lossless-no-decode only via
external-hardware passthrough (unbuilt); and the AC-3 companion is reliably
present (mandatory on Blu-ray) though you may need to split it from a combined
track. Nothing contradicts the AC-3-companion design already implemented.

## Deep code search across ALL of GitHub (the decisive test)

If a hidden Apple-native TrueHD path existed, code using it would exist. It does
not. GitHub code search (every public repo):

| Query | Hits | Meaning |
|---|---|---|
| `kAudioFormatMLP` | 2 — both **Symbian OS** dumps | No such constant in Apple CoreAudio anywhere |
| `TrueHD AudioConverterNew` (Swift) | **0** | Nobody decodes TrueHD with Apple's AudioConverter |
| `'mlp '` / `mlp trhd` AudioComponent | **0** | Nobody finds/registers an Apple MLP decoder component |
| `AV_CODEC_ID_TRUEHD` (Swift) | 10 — **all FFmpeg-based** | Every Swift TrueHD project decodes with FFmpeg |
| repo search: apple/ios/tvos truehd decoder | **0** | No Apple-native TrueHD decoder repo exists |

The 10 `AV_CODEC_ID_TRUEHD` hits are KSPlayer (+forks), SwiftFFmpeg, AetherEngine,
Rivulet — all FFmpeg. Notable in-code confirmations:
- **Rivulet** (`FFmpegRemuxSession.swift`): *"Audio transcode needed for DTS/TrueHD
  (AVPlayer can't decode them)."*
- **KSPlayer** maps TrueHD→`'mlpa'` `CMFormatDescription`, but the ASBD is built
  from **decoded PCM params** (`av_get_bytes_per_sample`) — FFmpeg decodes to PCM;
  `'mlpa'` is only a track-metadata tag, NOT compressed passthrough to Apple.

### Conclusion (code-level, all of GitHub)
No repository, fork, or hidden project plays TrueHD via an Apple decoder. Every
one that plays it bundles FFmpeg and decodes itself; the rest passthrough to an
external receiver. The "let Apple decode TrueHD" path produces zero code on
GitHub because the decoder does not exist.

## Deeper dig (round 2) — more variants, ObjC, Gitee, and AetherEngine

Conceding the fair point: GitHub code search is NOT exhaustive (default-branch
only, partial indexing, query quirks, private repos invisible). So these are
non-proof by absence — but every avenue still lands the same place:

- `kAudioFormatTrueHD` / `kAudioFormatDolbyTrueHD` / `kAudioFormatMlp`: **0**
- TrueHD + `AudioComponentFindNext`/`AudioComponentCount` (ObjC): **0**
- `'mlpa'` as a real `AudioStreamBasicDescription`/`AudioFormatID`: **0**
- Gitee / 码云 (Chinese host GitHub can't see): only a KSPlayer mirror (FFmpeg)

### AetherEngine — the most advanced 2026 reference, confirms the architecture
`superuser404notfound/AetherEngine` (iOS/tvOS/macOS engine, FFmpeg demux +
VideoToolbox). Its `AudioBridge.swift` for TrueHD:
- **FFmpeg decodes it**: `avcodec_find_decoder(srcCodecID)` + `avcodec_open2`.
  Apple does not decode TrueHD here.
- **Atmos objects dropped, bed survives**: "Atmos object metadata survives
  neither mode ... FFmpeg's EAC3 encoder produces no JOC."
- **Not passthrough**: "TrueHD/DTS aren't legal in fMP4 per ISOBMFF+HLS spec," so
  TrueHD takes a decode→resample→re-encode path (to EAC3/FLAC); only EAC3+JOC
  stays lossless via stream-copy.

This is exactly the design on this branch (FFmpeg handles the bitstream; Apple
never decodes TrueHD; objects are lost on decode).

## The point that doesn't depend on searching all of GitHub

You cannot search all of GitHub — true. But you don't need to. A repo cannot
make the OS decode a codec the OS lacks. The decisive facts are structural and
locally verifiable, not search-based:
- There is **no `kAudioFormatMLP`/TrueHD `AudioFormatID`** in any Apple SDK
  (the only hits anywhere are dead Symbian code).
- There is **no `'mlp '`/`'trhd'` `'adec'` AudioComponent** shipped by the OS —
  verifiable on YOUR device with `AudioDecoderProbe.swift`.

Therefore even an undiscovered/hidden repo could only do one of the three things
every visible repo does: bundle FFmpeg (decode itself), passthrough to external
hardware, or play the AC-3 companion via Apple's codec. None is "Apple decodes
TrueHD for free," because that capability is absent from the OS itself.

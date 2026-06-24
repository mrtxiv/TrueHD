# Fact-check (June 2026): every load-bearing claim in this repo, verified

Goal: be *sure* we've got things right, and look hard for a real breakthrough.
Each claim below was checked against primary sources (Apple docs, USPTO/patent
reporting, the actual source repos cited). Verdicts: ✅ confirmed, ❌ wrong,
⚠️ overstated / unverified.

## Core thesis — holds up

| # | Claim | Verdict | Basis |
|---|---|---|---|
| 1 | Apple ships **no** TrueHD/MLP decoder on any platform | ✅ | No public `kAudioFormatMLP`/`kAudioFormatTrueHD` AudioFormatID; no `'mlp '`/`'trhd'` `'adec'` component. Every player that plays TrueHD bundles FFmpeg/VLC/mpv. Confirm on-device with `AudioDecoderProbe.swift`. |
| 2 | Apple's own AC-3 / E-AC-3 / E-AC-3-JOC decoders need **no Dolby license for the app** | ✅ | Apple's platform license covers it; this is why the AC-3 companion path is license-free. |
| 3 | AC-3 patents expired (Mar 2017) | ✅ | EFF; last AC-3 patent expired 2017-03-20. |
| 4 | Commercial Blu-ray TrueHD tracks ship an AC-3 companion | ✅ | Mandatory on Blu-ray; but it is a **separate interleaved stream**, not a shared core — demuxer must surface/split it. |
| 5 | `AVSampleBufferAudioRenderer` accepts **compressed** buffers | ✅ | Apple: it "is used to decompress audio and play compressed or uncompressed audio." (Accepting ≠ passing through untouched to HDMI — see ❌2.) |
| 6 | Every real player decodes TrueHD itself or passes through to an AVR | ✅ | KSPlayer/FFmpegKit builds `--enable-decoder=truehd`; MPVKit, AetherEngine, Plozz, Reef bundle FFmpeg/VLC/mpv; VortX/Moonfin route TrueHD to external AVR. |

## Errors found — corrected in this commit

### ❌1  `AVAudioContentSource.passthrough` is **not** the HDMI bitstream switch
The original "breakthrough" hung on this symbol. Per the authoritative SDK diff
(dotnet/macios AVFAudio xcode26.0 b1), `AVAudioContentSource` lives in
**`AVAudioSettings.h`** as a value for the **audio ENCODER** key
`AVEncoderContentSourceKey` (alongside `AVEncoderDynamicRangeControlConfigurationKey`).
`AVAudioContentSource_Passthrough` means "passthrough content (use only if source
information is not available)" — i.e. a DRC/encoder content-type descriptor. It
has **nothing to do with HDMI bitstream-out**. Decisively, the same SDK diff
shows **no new passthrough API on AVAudioSession, AVAudioFormat, AVPlayer, or
AVSampleBufferAudioRenderer**. The press coverage (FlatpanelsHD/AppleInsider)
named this enum as "the passthrough API" by pattern-matching the name — and this
repo inherited that error. *Corrected in `BREAKTHROUGH.md`,
`TrueHDPassthroughRenderer.swift`, `TrueHDPassthrough.swift`.*

(Self-check note: an earlier version of this file said the enum is "the
`contentSource` value of AVAudioConverter." More precisely it's the
`AVEncoderContentSourceKey` in AVAudioSettings.h; AVAudioConverter consumes
encoder settings, so it surfaces there too, but the canonical home is the encoder
keys. The conclusion — DRC descriptor, not a bitstream switch — is unchanged.)

### ❌2  "MLP lossless core expired ~2017" → the bundled-decoder path is **not** provably patent-clean
This was the legal foundation for the `decoder-core/` (truehdd) "lossless" tier.
It does not hold — though the honest verdict is **"uncertain," not "definitely
encumbered to 2046"** (correcting my own first pass, which overstated this):
- The *original* MLP patents (filed ~1998) have **largely lapsed**. So the repo's
  "MLP core expired ~2017" is partly right for the original core.
- BUT TrueHD as actually encoded (MLP **FBA**, 16-ch) adds later coding tools
  whose patent status is **not all confirmed expired**, and "MLP/TrueHD is still
  covered by several patents" per multiple sources. The exact expiry of the
  specific patents needed to decode a modern TrueHD stream is **unresolved here**.
- ⚠️ Self-correction: the "**through December 2046**" figure is Dolby's **entire
  issued patent portfolio** (from their 10-K) — Atmos, AC-4, Dolby Vision, etc. —
  **not** specifically the TrueHD/MLP lossless decode. My earlier wording implied
  2046 applies to TrueHD decode; that was a conflation. Atmos *objects* are the
  clearly-live-to-~2046 part; the lossless **bed** decode is genuinely uncertain.
- The `truehdd` crate's **own authors** state (verified verbatim in its README)
  it "is **not intended for production environments or consumer playback
  systems**." Licensed Apache-2.0.
- Apache-2.0 grants **copyright** and only the *contributors'* patent rights —
  **not Dolby's**. A permissive license does not make a patented algorithm
  royalty-free to ship.

Net: "bundle truehdd and ship lossless TrueHD, license-free" is **not safe to
claim** — but neither is "definitely infringing." It is **legally uncertain**;
treat the bundled-decoder tier as research-only unless cleared by counsel.

### ⚠️3  Fabricated / unverifiable code citations in the "breakthrough" evidence
The strongest-sounding evidence was specific quotes from named source files.
Checked — they do not hold up:
- **"Rivulet (`FFmpegAudioDecoder.swift`, `DirectPlayPipeline.swift`,
  `FFmpegRemuxSession.swift`)"** with the quote about AVSampleBufferAudioRenderer
  being "silent on AirPlay": a real `Rivulet` (l984-451/Rivulet) exists but it's
  an **MPV-based** Plex/Live-TV app; the cited Swift files and quotes were **not
  found**. Treat those quotes as **unverified / likely fabricated**.
- **"Moonfin-Core (`AppleTvVideoChannel.swift`) →
  `configurePreferredBackendForNextPlayback(.native)`"**: Moonfin is real but is
  **Flutter + MPVKit**, not native Swift; the cited file/method was not found.
  ⚠️ Self-correction: my first pass cited Moonfin Smart-TV issue #179 ("Playback
  fails with TrueHD") as Apple TV evidence — but the **Smart-TV repo targets
  Tizen/webOS (Samsung/LG), NOT Apple TV/tvOS**, so #179 is irrelevant to the
  Apple-TV passthrough question. Withdrawn. The citation remains unverified
  regardless.
- **`kAudioCodecContentSource_Passthrough = 42`** (specific enum value):
  unverified; do not rely on the literal value.

What *is* real and does corroborate the architecture: **AetherEngine**
(`superuser404notfound/AetherEngine`) — it FFmpeg-demuxes, stream-copies
**E-AC-3+JOC** for Atmos passthrough on every route, and for **TrueHD it bridges
(transcodes) to E-AC-3/FLAC** rather than passing it through. I.e. even the most
advanced 2026 engine does **not** bitstream-passthrough TrueHD.

## Is there a real breakthrough? — No magic door, but one genuinely useful path

The exact dream — *lossless TrueHD + app decodes nothing + no AVPlayer + no
external hardware* — is still the empty set, and even the *with-AVR, no-AVPlayer*
version is **unproven**. The iOS/tvOS 26 SDK diff shows **no** new passthrough
API on AVAudioSession/AVAudioFormat/AVPlayer/AVSampleBufferAudioRenderer; Swiftfin
#1641 / KSPlayer #862 are still open with no sample; and even Dolby's own
`daaplay` decodes to PCM and explicitly does **not** use AVSampleBufferAudioRenderer
or passthrough.

The closest thing to a breakthrough that is **real, shippable today, and matches
your constraints** is the one AetherEngine actually ships:

> **E-AC-3 + JOC (Dolby Digital Plus with Atmos) handled entirely by Apple.**
> No app decode, no Dolby license (Apple's platform license), **Atmos objects
> preserved**, works on **all** current Apple platforms, **no tvOS 26 needed**.

Many TrueHD titles carry the *same* Atmos mix in a DD+JOC track (or you accept
DD+ instead of the AC-3 5.1). Selecting/playing that track via Apple's codec gets
you **Atmos, losslessly routed, license-free** — strictly better than the AC-3
5.1 companion, while keeping every "Apple does everything" constraint. It is not
*TrueHD-lossless*, but it is the best real-world audio you can ship with zero
decode and zero license. **Bonus:** E-AC-3's last patent (US7516064) is
**reportedly** expired as of 2026-01-30 (Phoronix; headline says "might now be
expired") — moot anyway, since Apple's platform license already covers the app.

## Net

- The repo's **architecture is sound**: passthrough-if-capable (experimental on
  tvOS 26), else AC-3/E-AC-3 demux via Apple, no HLS, no AVPlayer, no license.
- **Fix the legal overclaim** on the bundled truehdd tier (done below).
- **Drop the fabricated citations**; keep AetherEngine as the real corroboration.
- **Add a DD+/E-AC-3-JOC tier** as the highest-quality license-free path — that's
  the genuine, ship-today win.

## Fact-check of this fact-check (self-audit)

Re-verified the load-bearing claims against primary sources. Outcome:

| Claim | Re-check result |
|---|---|
| `AVAudioContentSource` is a DRC/encoder descriptor, not a bitstream switch | ✅ **Strengthened.** SDK diff (dotnet/macios AVFAudio xcode26.0 b1) confirms it's `AVEncoderContentSourceKey` in `AVAudioSettings.h`, and shows **no** passthrough API on AVAudioSession/AVPlayer/AVSampleBufferAudioRenderer. (Fixed my imprecise "AVAudioConverter.contentSource" wording.) |
| truehdd is "not intended for production/consumer playback," Apache-2.0 | ✅ **Verified verbatim** in its README. |
| AC-3 patents expired 2017 | ✅ Holds (EFF). |
| TrueHD/MLP patented "through ~2046" | ⚠️ **Overstated — corrected.** 2046 is Dolby's *whole* portfolio, not TrueHD-decode. Honest verdict: lossless-bed decode is **legally uncertain**, not provably encumbered to 2046. |
| Moonfin #179 "TrueHD fails" as Apple TV evidence | ❌ **Withdrawn.** The Smart-TV repo is **Tizen/webOS**, not Apple TV. Irrelevant; removed. |
| Rivulet/Moonfin Swift-file quotes | ✅ Kept as "unverified/likely fabricated" (couldn't confirm ≠ proof of fabrication; wording is appropriately hedged). |
| AetherEngine transcodes TrueHD, stream-copies E-AC-3+JOC | ✅ Holds (its README). |
| E-AC-3 last patent expired 2026-01-30 | ⚠️ Softened to "reportedly" (Phoronix "might now be expired"). Moot for the app anyway. |
| Dolby daaplay decodes to PCM, no AVSampleBufferAudioRenderer/passthrough | ✅ Holds (its docs list that integration under "does not implement"). |

Net of the self-audit: the **central conclusions are unchanged and better
sourced** (no Apple TrueHD decoder; no confirmed tvOS 26 passthrough API; AC-3/
E-AC-3-via-Apple is the real license-free path). Two secondary points were
overstated and are now corrected: the **2046 patent scope** and the **misattributed
Moonfin bug**.

### Sources
- [AVAudioConverter](https://developer.apple.com/documentation/avfaudio/avaudioconverter) ·
  [AVAudioContentSource.passthrough](https://developer.apple.com/documentation/avfaudio/avaudiocontentsource/passthrough) ·
  [SDK diff: AVFAudio xcode26.0 b1 (dotnet/macios)](https://github.com/dotnet/macios/wiki/AVFAudio-iOS-xcode26.0-b1)
- [AVSampleBufferAudioRenderer](https://developer.apple.com/documentation/avfoundation/avsamplebufferaudiorenderer)
- [Swiftfin #1641](https://github.com/jellyfin/Swiftfin/issues/1641) · [KSPlayer #862](https://github.com/kingslay/KSPlayer/issues/862)
- [Dolby daaplay (decodes to PCM, no passthrough)](https://github.com/DolbyLaboratories/daaplay)
- [AetherEngine](https://github.com/superuser404notfound/AetherEngine) · [truehdd (research-only)](https://github.com/truehdd/truehdd)
- [AC-3 patent expiry 2017 (EFF)](https://freetoairamerica.wordpress.com/2017/03/20/electronic-frontier-foundation-the-patent-on-dolby-digital-ac-3-has-just-expired/) ·
  [E-AC-3 last patent reportedly expired 2026-01-30 (Phoronix)](https://www.phoronix.com/news/Dolby-Digital-Plus-E-AC3-2026)
- [MLP/TrueHD patents (Wikipedia)](https://en.wikipedia.org/wiki/Meridian_Lossless_Packing) ·
  [Dolby whole-portfolio patents through 2046 — 10-K, NOT TrueHD-specific](https://s27.q4cdn.com/365963565/files/doc_financials/2022/q4/5ac8daf9-e853-43df-b76c-93df1280669f.pdf)

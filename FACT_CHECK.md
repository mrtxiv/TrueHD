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
The original "breakthrough" hung on this symbol. It is actually the
`contentSource` value of **`AVAudioConverter`**, controlling **Dynamic Range
Compression (DRC)**. Its sibling values are `.spatial`, `.traditional`,
`.capture`, `.music`, etc.; `.passthrough` means "apply DRC without tailoring it
to a content type." It has nothing to do with HDMI bitstream-out. The press
coverage (FlatpanelsHD/AppleInsider) that named it as "the passthrough API" is
where this repo's error came from — they pattern-matched the name to the rumored
feature. *Already corrected in `BREAKTHROUGH.md`, `TrueHDPassthroughRenderer.swift`,
`TrueHDPassthrough.swift` in the prior commit; restated here for the record.*

### ❌2  "MLP lossless core expired ~2017" → the bundled-decoder path is **not** provably patent-clean
This was the legal foundation for the `decoder-core/` (truehdd) "lossless" tier.
It does not hold:
- TrueHD/MLP **remains under multiple live Dolby patents** — Dolby's issued
  patents run "at various times **through December 2046**." The *original* MLP
  patents (filed ~1998) have largely lapsed, but TrueHD as actually encoded
  (MLP **FBA**, 16-ch) uses later coding tools that are not all expired.
- The `truehdd` crate's **own authors** state it "is **not intended for
  production environments or consumer playback systems**" and is "for research
  and development purposes."
- Apache-2.0 grants **copyright** rights and only the *contributors'* patent
  rights — explicitly **not Dolby's**. A permissive license does not make a
  patented algorithm royalty-free to ship.

So "bundle truehdd and ship lossless TrueHD, license-free" is **not safe to
claim**. Treat the bundled-decoder tier as research-only unless cleared by
counsel. The Atmos-objects-to-2046 caveat the repo already had is correct but
was the *smaller* problem — the lossless **bed decode itself** is the bigger
uncertainty.

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
  **Flutter + MPVKit**, not native Swift; the cited file/method was not found,
  and its Smart-TV variant has an **open bug "Playback fails with TrueHD audio
  codec"** (#179). The specific citation is unverified.
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
version is **unproven** (no public tvOS 26 enable API; Swiftfin #1641 / KSPlayer
#862 still open; even Dolby's own `daaplay` decodes to PCM and explicitly does
**not** use AVSampleBufferAudioRenderer or passthrough).

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
decode and zero license. **Bonus:** E-AC-3's last patent (US7516064) expired
2026-01-30, so E-AC-3 is now patent-free too — though moot, since Apple's license
already covers the app.

## Net

- The repo's **architecture is sound**: passthrough-if-capable (experimental on
  tvOS 26), else AC-3/E-AC-3 demux via Apple, no HLS, no AVPlayer, no license.
- **Fix the legal overclaim** on the bundled truehdd tier (done below).
- **Drop the fabricated citations**; keep AetherEngine as the real corroboration.
- **Add a DD+/E-AC-3-JOC tier** as the highest-quality license-free path — that's
  the genuine, ship-today win.

### Sources
- [AVAudioConverter / contentSource (DRC)](https://developer.apple.com/documentation/avfaudio/avaudioconverter) ·
  [AVAudioContentSource.passthrough](https://developer.apple.com/documentation/avfaudio/avaudiocontentsource/passthrough)
- [AVSampleBufferAudioRenderer](https://developer.apple.com/documentation/avfoundation/avsamplebufferaudiorenderer)
- [Swiftfin #1641](https://github.com/jellyfin/Swiftfin/issues/1641) · [KSPlayer #862](https://github.com/kingslay/KSPlayer/issues/862)
- [Dolby daaplay (decodes to PCM, no passthrough)](https://github.com/DolbyLaboratories/daaplay)
- [AetherEngine](https://github.com/superuser404notfound/AetherEngine) · [truehdd (research-only)](https://github.com/truehdd/truehdd)
- [AC-3 patent expiry 2017 (EFF)](https://freetoairamerica.wordpress.com/2017/03/20/electronic-frontier-foundation-the-patent-on-dolby-digital-ac-3-has-just-expired/) ·
  [E-AC-3 last patent expired 2026-01-30 (Phoronix)](https://www.phoronix.com/news/Dolby-Digital-Plus-E-AC3-2026)
- [MLP/TrueHD patents (Wikipedia)](https://en.wikipedia.org/wiki/Meridian_Lossless_Packing) ·
  [Dolby patents through 2046 (10-K)](https://s27.q4cdn.com/365963565/files/doc_financials/2022/q4/5ac8daf9-e853-43df-b76c-93df1280669f.pdf)
</content>
</invoke>

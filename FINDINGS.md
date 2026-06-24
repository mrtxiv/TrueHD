# Playing Dolby TrueHD on Apple platforms (iOS / macOS / tvOS): what is and isn't possible

A rigorous, source-backed decision record. The question: can a media player
play **lossless** TrueHD on all three Apple platforms while keeping all of:

1. Full lossless TrueHD (ideally incl. Atmos height objects)
2. iOS **and** macOS **and** tvOS
3. App does not run MLP decode in code *you* wrote
4. Legal: no patent infringement, no paid Dolby license, App-Store-shippable
5. No external hardware (AV receiver) to decode
6. No GPL/LGPL decoder bundled

## TL;DR

**No single configuration satisfies all six.** The constraints are
over-determined and exactly one must give. The binding wall is **physics +
patents**, not a missing API: for audio to exist, an inverse-MLP *decode* must
run somewhere, and Apple ships no TrueHD decoder on any platform.

| If you relax... | You get | Cost |
| --- | --- | --- |
| **#6** (allow non-GPL bundled decoder) | Lossless bed, all 3 platforms, on-device, no license | Something decodes — but via Apache-2.0 `truehdd`, **not GPL/LGPL**, **not your code**. Atmos objects still patent-encumbered. |
| **#5** (allow external hardware) | Lossless + Atmos *(if it works)* | tvOS 26 only, bitstream to an AVR; **unproven for lossless TrueHD** (no shipping impl; betas expose no toggle); not iOS/macOS |
| **#1** (allow lossy) | AC-3/E-AC-3 companion via Apple's *own* decoder | Lossy 5.1; **the only** option needing no decode-by-you, no hardware, all 3 platforms |
| **#4b** (pay Dolby) | Lossless + Atmos, all platforms, on-device | A paid Dolby (and DTS) license — **this is what Infuse does** |

## The facts, with sources

### Apple ships no TrueHD decoder — and no DTS decoder either
- CoreAudio/AudioToolbox decode **AC-3, E-AC-3, and E-AC-3 JOC** only. No
  public `kAudioFormatMLP`/`kAudioFormatTrueHD` `AudioFormatID` exists, so a
  TrueHD stream cannot even be *described* to CoreAudio with public API.
  ([Apple AudioFormatID](https://developer.apple.com/documentation/coreaudiotypes/audioformatid),
  [CoreAudioBaseTypes.h](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS13.0.sdk/System/Library/Frameworks/CoreAudioTypes.framework/Headers/CoreAudioBaseTypes.h))
- iOS/macOS also have **no native DTS decoder** — so "transcode TrueHD -> DTS"
  buys nothing, and it still requires decoding the TrueHD first.
  ([Apple Developer Forums 18423](https://developer.apple.com/forums/thread/18423))

### "Apple has APIs / tricks" — what they actually are
- `AudioComponentRegister` + `AudioCodec.h` let you register **your own** codec
  with the OS. They do not expose a hidden Apple TrueHD decoder; they're the
  socket a decoder *you bring* plugs into.
  ([AudioComponentRegister](https://developer.apple.com/documentation/audiotoolbox/1410487-audiocomponentregister))

### The DTS-patent-expiry angle is dead three ways
- Only old DTS **Core** patents lapsed; open decoders (`libdca`, `dcadec`)
  still warn US users they need a DTS license.
  ([VideoLAN libdca](https://www.videolan.org/developers/libdca.html))
- Apple can't play DTS regardless (see above).
- It still requires decoding the TrueHD first.

### The one proven shipping app does it by licensing, not by a trick
- **Infuse** plays lossless TrueHD/DTS-HD MA by **decoding in its own code under
  paid Dolby + DTS licenses**, outputting LPCM. If a free Apple SPI existed, the
  platform's most capable player wouldn't be paying for licenses.
  ([Firecore](https://community.firecore.com/t/can-infuse-pro-play-dts-hd-master-audio-and-dolby-truehd-sound-tracks/17384/4),
  [Firecore support](https://support.firecore.com/hc/en-us/articles/217735707-Audio-Options-Capabilities))

### tvOS 26 passthrough = external hardware, tvOS only, and unproven for lossless TrueHD
- tvOS 26 passthrough is intended to send a bitstream to an AVR, which decodes.
  It needs external hardware (fails #5) and is tvOS-only (fails #2).
  ([FlatpanelsHD](https://www.flatpanelshd.com/news.php?subaction=showfull&id=1749568309),
  [Swiftfin #1641](https://github.com/jellyfin/Swiftfin/issues/1641))
- **Caveat (verified):** whether it carries **lossless** TrueHD/DTS-HD MA (vs.
  just DD/DD+/DTS) is **unconfirmed**. Early betas reportedly expose no toggle;
  observers note macOS does not passthrough TrueHD/DTS. The two tracking issues
  (Swiftfin #1641, KSPlayer #862) are **both closed with no implementation**. The
  `AVAudioContentSource` enum and `kAudioCodecContentSource_Passthrough = 42` are
  real SDK symbols, but no shipping code drives lossless TrueHD through them. See
  `VERIFICATION.md`.

### Licenses & patents on the bundled-decoder path
- `truehdd` / `truehd` crate is **Apache-2.0** — permissive, App-Store-clean,
  satisfies #3 and #6. ([crates.io](https://crates.io/crates/truehd),
  [github](https://github.com/truehdd/truehdd))
- Apache-2.0's patent grant covers only the contributors' patents, **not
  Dolby's**. ([Apache FAQ](https://www.apache.org/foundation/license-faq.html))
- Foundational **MLP lossless patents expired ~2017**, so the lossless **bed**
  is very likely patent-clear. ([Wikipedia: MLP](https://en.wikipedia.org/wiki/Meridian_Lossless_Packing))
- **Atmos object (OAMD) patents remain in force** (filings from the 2010s run
  ~20 years, i.e. well into the 2030s–2040s) and Dolby still licenses object
  decoding — so on-device Atmos *objects* cannot be both free and patent-clean.
  (A precise "expires in YYYY" date should be confirmed per-patent at the USPTO;
  the durable fact is that object decoding is still licensed, which is why even
  Infuse decodes only the bed and drops Atmos objects.)
  ([Dolby 10-K](https://s27.q4cdn.com/365963565/files/doc_financials/2022/q4/5ac8daf9-e853-43df-b76c-93df1280669f.pdf))
- GPL/LGPL + App Store is a real, never-cleanly-resolved conflict (VLC), which
  is why FFmpeg's LGPL decoder is the wrong choice and Apache-2.0 is the right
  one. ([FSF on VLC](https://www.fsf.org/blogs/licensing/vlc-enforcement))

## The private-Apple-decoder claim

No credible evidence Apple ships a reachable TrueHD `AudioComponent`. Run
`AudioDecoderProbe.swift` in this repo on a real device to check empirically.
Expected result: AC-3 / E-AC-3 / E-AC-3 JOC present, **no** `'mlp '`/`'trhd'`.
Even if one appeared, it would be undocumented SPI -> App Review **2.5.1** ->
not shippable. "Works in a debug build" != shippable.

## Recommendation

- **Want lossless bed, all platforms, on-device, no license, no LGPL:** bundle
  Apache-2.0 `truehdd`, decode to PCM, fold objects to the bed. Keeps 1(bed)/2/3/5/6;
  #4's patent clause is well-supported but not lawyer-certified for the bed.
- **Need real Atmos objects legally:** there is no free door — license Dolby
  (be Infuse) or passthrough to an AVR on tvOS. The object patents are live.

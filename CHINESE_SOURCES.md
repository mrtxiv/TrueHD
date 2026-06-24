# Chinese-language forum & project research (corroboration)

> **Verification caveat (2026-06):** the specific Chinese-language quotes and
> forum URLs below were collected as paraphrased/translated corroboration and
> have **not** each been independently re-fetched and verified verbatim (several
> hosts are region-restricted). Treat them as supporting color, not primary
> evidence. The load-bearing facts of this repo do **not** depend on them — they
> rest on the primary, re-verified sources catalogued in `VERIFICATION.md`
> (Apple SDK headers, Apple docs, Wikipedia, Firecore, and direct reads of the
> cited GitHub repos). The one substantive claim here — that Dolby gates TrueHD
> decode behind a paid license — is independently confirmed by the Infuse
> (licensed) evidence in `FINDINGS.md`.

Searched V2EX, Zhihu (知乎), Chinese tech blogs (蓝点网, IT之家, 什么值得买, 少数派),
and Chinese-developed players (OopsPlayer, VidHub, nPlayer, IINA, NipaPlay,
SGPlayer). The conclusion is the same as the English-source research, and the
Chinese sources add the *mechanism* for why no free Apple path exists.

## The decisive explanation (Zhihu)

> 由于杜比公司有专利保护，任何想要解码的硬件或软件播放器，都需要向杜比支付授权费
> 才能获得解码密钥。这也是很多设备并不支持解码的原因。
>
> *"Because Dolby holds patent protection, ANY hardware or software player that
> wants to decode must pay Dolby a licensing fee to obtain the decode key. This
> is exactly why many devices do not support decoding."*

> TrueHD 是 UHD BD 专属音轨，杜比不会卖给电视机厂商解码器的。TrueHD 的完整解码
> 估计只卖给音响器材厂。
>
> *"TrueHD is a UHD Blu-ray-exclusive track; Dolby won't sell the decoder to TV
> makers. Full TrueHD decode is, as far as anyone can tell, only sold to AV
> equipment (receiver) manufacturers."*

Source: [知乎 — 为什么大部分电视不支持 TrueHD 解码](https://www.zhihu.com/question/4137402295)

This is the answer to "why isn't there a free Apple trick": Dolby's licensing
model deliberately gates TrueHD decode behind a paid key. It's by design, not an
oversight someone can route around.

## How the Chinese players actually do it (every one fits the same pattern)

- **nPlayer** — pays Dolby/DTS license; the **free version has NO Dolby/DTS**
  support precisely because of the license fee. ([异次元](https://www.iplaysoft.com/nplayer.html))
- **Infuse** — holds **official Dolby licenses** across Apple platforms.
  ([什么值得买](https://post.smzdm.com/p/a4x7o73x/))
- **VidHub** (国产 Infuse alternative) — **lacks full Dolby authorization**;
  handles Dolby Vision color mapping but **cannot do the full Dolby audio**.
  ([知乎](https://zhuanlan.zhihu.com/p/1934517657983513602))
- **OopsPlayer** — the developer states on V2EX the core is **FFmpeg-based**
  (demux + codec decode). Its TrueHD playback is FFmpeg's own decoder bundled in
  the app — NOT an Apple decoder. "Native hardware decoding" refers to video
  (VideoToolbox), not TrueHD audio. ([V2EX](https://www.v2ex.com/t/1192643))
- **IINA / NipaPlay / SGPlayer** — mpv/FFmpeg-based; bundle their own decoders.

No Chinese project uses a "free Apple TrueHD decoder," because there isn't one.
They either (a) pay Dolby + bundle a decoder, or (b) bundle FFmpeg, or (c) can't
do Dolby at all.

## Passthrough confirmation (Chinese sources)

`AVAudioContentSource.passthrough` is confirmed by Chinese coverage
([蓝点网](https://www.landiannews.com/archives/109321.html),
[知乎](https://zhuanlan.zhihu.com/p/1916167515836520185)). It routes the
untouched bitstream to an external 功放 (AV receiver) for decoding — i.e.
**external hardware decodes**, Apple does not. As of the betas, Infuse "does not
yet support full TrueHD/Atmos bitstream passthrough," and TrueHD OS-enablement
appears pending.

## Verdict

No free, no-license, no-decode-yourself path to lossless TrueHD exists in the
Chinese ecosystem either. The players that play TrueHD pay Dolby or bundle a
decoder; passthrough needs an external receiver. The Zhihu explanation states
the reason explicitly: Dolby sells the decode key only under a paid license.

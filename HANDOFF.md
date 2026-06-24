# Handoff: playing Dolby TrueHD audio in a media player on Apple platforms

This document is a self-contained brief. Hand it to a developer with no prior
context and they can build the audio path.

## 1. The goal

Play the audio of files that contain a **Dolby TrueHD** track in a media player
on **iOS, macOS, and tvOS**. Hard rule from the product owner: **our app must
not decode the audio itself and must not bundle any audio decoder.** Apple's
operating system may decode; we may not.

## 2. The hard truth (read this first — it determines everything)

- **Apple ships NO Dolby TrueHD decoder** on any platform. CoreAudio /
  AudioToolbox can decode AC-3 (Dolby Digital) and E-AC-3 (Dolby Digital Plus)
  only. There is not even a format identifier for TrueHD in the public SDK.
- Therefore, **lossless TrueHD cannot play on-device unless something decodes
  it.** If our app may not decode, and Apple can't, then on-device lossless
  TrueHD is impossible. This is a physical fact, not a missing feature.
- **The chosen solution:** play the **AC-3 / E-AC-3 companion track** that ships
  alongside the TrueHD, using **Apple's own decoder**. Our app decodes nothing.
  The trade-off we accept: this is lossy 5.1 Dolby Digital, not lossless TrueHD.
  (Lossless TrueHD is only possible by either bundling a decoder — forbidden —
  or passing the bitstream to an external AV receiver on tvOS, which needs extra
  hardware. Both are out of scope here.)

## 3. Where the AC-3 comes from

A TrueHD title almost always includes a Dolby Digital companion, in one of two
forms:

1. **A separate AC-3 or E-AC-3 track** in the container (common in MKV files).
   Just select that track.
2. **An AC-3 "core" embedded inside the TrueHD stream.** On Blu-ray, a TrueHD
   track is required to carry an AC-3 core for legacy decoders, so this always
   exists on disc-sourced content. You extract the AC-3 substream from the
   combined stream.

If a file is genuinely TrueHD-only with no AC-3 anywhere (rare), this approach
has nothing to play — there is no audio without decoding TrueHD.

## 4. The pipeline (what to build)

```
Container (MKV/M2TS/MP4)
      │   demux = parse only, NOT decode
      ▼
AC-3 / E-AC-3 access units (one syncframe = 1536 samples each)
      │   hand each packet to Apple's codec
      ▼
Apple's AudioConverter  →  interleaved Float32 PCM
      │
      ▼
Ring buffer  →  output AudioUnit  →  speakers
```

Step by step:

1. **Demux.** Use a demuxer (FFmpeg's libavformat, or a custom MKV/M2TS parser)
   to read the container and emit AC-3/E-AC-3 packets from the selected audio
   track. Demuxing is container parsing; it does not run the Dolby algorithm, so
   it complies with "we do not decode." (If using FFmpeg, use it for DEMUX ONLY,
   not its decoders.)
2. **Decode with Apple's codec.** For each AC-3/E-AC-3 packet, call Apple's
   `AudioConverter` (input format `kAudioFormatAC3` or `kAudioFormatEnhancedAC3`,
   output 32-bit float PCM). Apple performs the decode. Result: interleaved
   Float PCM, typically 48 kHz, 6 channels (5.1).
3. **Buffer and render.** Write the PCM into a single-producer/single-consumer
   ring buffer. An output AudioUnit (`DefaultOutput` on macOS,
   `RemoteIO` on iOS/tvOS) pulls from the ring on the realtime audio thread and
   plays it. No AVPlayer, no AVFoundation playback object required.

## 5. Reference implementation (already written)

These Swift files implement steps 2–3; the only thing left to write is the
demuxer's "give me the next AC-3 packet" method.

- `apple/swift/AC3ConverterCore.swift` — pure AudioToolbox. Feed one AC-3/E-AC-3
  access unit, get interleaved Float PCM back. Apple's codec does the decode.
- `apple/swift/AC3DecodePipeline.swift` — wires a packet source → AC3ConverterCore
  → ring buffer → output AudioUnit. Call `start()` and audio plays.
- `apple/swift/AudioDecoderProbe.swift` — run once on each target device to
  confirm the AC-3/E-AC-3 decoder is present (look for an `adec` component with
  subtype `ac-3` / `ec-3`).

The developer implements one protocol:

```swift
protocol AC3PacketSource: AnyObject {
    func nextPacket() -> Data?   // next AC-3/E-AC-3 access unit, or nil at end
}
```

and starts playback:

```swift
let pipeline = AC3DecodePipeline(codec: .ac3,   // .eac3 for Dolby Digital Plus
                                 source: myDemuxer,
                                 sampleRate: 48_000,
                                 channels: 6)
try pipeline?.start()
```

## 6. Things to verify before shipping

1. **Decoder presence on iOS/tvOS.** Run `AudioDecoderProbe.swift` on the
   minimum-supported device. AC-3/E-AC-3 decode is guaranteed on macOS; confirm
   on your iOS/tvOS targets. If a device lacks the standalone decoder, fall back
   to remuxing the AC-3 into a small local MP4/HLS and letting `AVPlayer` decode.
2. **Channel layout.** The companion is usually 5.1 (6 channels). Read the real
   layout from the track; don't hardcode if you support other layouts.
3. **Ring buffer.** The reference ring buffer uses a lock for simplicity. For
   production realtime audio, replace the lock with atomic index updates.
4. **A/V sync.** Drive audio from the decoded sample clock; sync video to it.
5. **No companion track.** Handle the rare TrueHD-only file gracefully (no audio
   or a user-facing message), since this path cannot decode TrueHD.

## 7. One-paragraph summary to say out loud

"Apple has no TrueHD decoder, so we can't play lossless TrueHD on-device without
writing or bundling a decoder, which we won't. Instead we play the AC-3 / Dolby
Digital companion track that ships with the TrueHD, and we let Apple's built-in
decoder handle it. Our app only demuxes the container to pull out the AC-3
packets and hands them to Apple's AudioConverter, which returns PCM that we play
through an output AudioUnit. It's lossy 5.1 instead of lossless, but it plays on
iOS, macOS, and tvOS with no decoder of our own and no extra hardware."

# Wiring guide: building the AC-3 path (FFmpeg demux + Apple decode, no AVPlayer)

Goal: compile the C demuxer shim, expose it to Swift, link FFmpeg (demux libs
only), and call the pipeline. Your app decodes nothing — Apple's AudioToolbox
decodes; FFmpeg only demuxes.

## Files involved
- `apple/src/ffmpeg_ac3_demux.c` + `apple/include/ffmpeg_ac3_demux.h` — demuxer
- `apple/include/module.modulemap` — exposes the C headers to Swift
- `apple/swift/*.swift` — `FFmpegAC3Source`, `AC3ConverterCore`,
  `AC3DecodePipeline`, etc.

## FFmpeg libraries you must link
Dynamic-link these (LGPL — demuxer only; no Dolby decoder is used):
- `libavformat`  (container demuxing)
- `libavcodec`   (for `AVCodecParameters` / `AV_CODEC_ID_*` — no decoder opened)
- `libavutil`

You need iOS/tvOS/macOS builds of FFmpeg. Options:
- Prebuilt xcframeworks (e.g. `ffmpeg-kit`-style or `mobile-ffmpeg` successors).
- Build FFmpeg yourself with `--enable-shared --disable-everything
  --enable-demuxer=matroska,mpegts,mov --enable-parser=ac3` (minimal demux-only
  config keeps it small and avoids bundling decoders entirely).

> Tip: a demux-only FFmpeg build (no `--enable-decoder=*`) makes "we never
> decode" structurally true — the Dolby decoders aren't even compiled in.

## Option A — Xcode app target (bridging header)
1. Add `ffmpeg_ac3_demux.c` to the target's Compile Sources.
2. Create/extend a bridging header (`YourApp-Bridging-Header.h`):
   ```c
   #import "ffmpeg_ac3_demux.h"
   ```
   Set it under Build Settings → "Objective-C Bridging Header".
3. Add `apple/include` to Build Settings → "Header Search Paths".
4. Link `libavformat`, `libavcodec`, `libavutil` (add the xcframeworks or
   `.dylib`s and their headers' search path).
5. Use the Swift files as-is.

(With a bridging header you don't need the module.modulemap; use one or the
other. The modulemap is for SwiftPM / framework targets.)

## Option B — Swift Package Manager
1. A C target for the shim:
   ```swift
   .target(
       name: "TrueHDCShims",
       path: "apple",
       sources: ["src/ffmpeg_ac3_demux.c"],
       publicHeadersPath: "include"
   )
   ```
2. A `.systemLibrary` (or xcframework binary target) for FFmpeg, with a
   modulemap that lists `libavformat`/`libavcodec`/`libavutil` and `link`s them.
3. A Swift target depending on both `TrueHDCShims` and the FFmpeg module, holding
   the `apple/swift/*.swift` files.

## Use it
```swift
// MP4/MOV — fully Apple-native, no FFmpeg needed:
let p1 = AC3DecodePipeline.makeFromMP4(url: mp4URL)

// MKV/M2TS/TS — FFmpeg demuxes, Apple decodes:
let p2 = AC3DecodePipeline.makeWithFFmpeg(url: mkvURL)

try p2?.start()   // sound comes out; your app never decoded anything
```

## Verify on-device first
Run `AudioDecoderProbe.swift` on your minimum iOS/tvOS target and confirm an
`adec` component with subtype `ac-3` / `ec-3` exists. Present on macOS; verify
on iOS/tvOS. If absent on a device, remux the AC-3 into a local fragmented MP4
and read it with `AVAssetReaderAC3Source` instead.

## FFmpeg version note
`ffmpeg_ac3_demux.c` uses the FFmpeg 5.1+ channel API (`ch_layout.nb_channels`).
On older FFmpeg, change it to `codecpar->channels`.

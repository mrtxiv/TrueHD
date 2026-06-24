# Building the TrueHD decode core for iOS / macOS / tvOS

Goal: one `.xcframework` wrapping the Apache-2.0 Rust decoder, linkable from a
Swift app on all three platforms. No GPL/LGPL, no decoder you wrote, on-device.

## 0. Prereqs
```sh
rustup toolchain install stable
rustup toolchain install nightly          # tvOS needs nightly (see step 3)
```

## 1. macOS + iOS (Tier 2 — stable Rust)
```sh
rustup target add aarch64-apple-darwin x86_64-apple-darwin \
                  aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

cd decoder-core
for T in aarch64-apple-darwin x86_64-apple-darwin \
         aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  cargo build --release --target "$T"
done
```

## 2. tvOS (Tier 3 — nightly + build-std)
tvOS targets are Rust **Tier 3**: no prebuilt std, so build it from source.
Ref: https://doc.rust-lang.org/beta/rustc/platform-support/apple-tvos.html
```sh
rustup component add rust-src --toolchain nightly
cd decoder-core
cargo +nightly build --release -Z build-std=std,panic_abort \
      --target aarch64-apple-tvos
cargo +nightly build --release -Z build-std=std,panic_abort \
      --target aarch64-apple-tvos-sim
```
This is the one place that costs real effort; Tier 3 carries no automated-test
guarantee from the Rust project — validate the tvOS slice on device.

## 3. Assemble the xcframework
Lipo the per-arch `libtruehd_decoder_core.a` into per-platform fat libs (device
vs simulator must stay separate), then:
```sh
xcodebuild -create-xcframework \
  -library macos/libtruehd_decoder_core.a   -headers ../apple/include \
  -library ios-device/libtruehd_decoder_core.a -headers ../apple/include \
  -library ios-sim/libtruehd_decoder_core.a    -headers ../apple/include \
  -library tvos-device/libtruehd_decoder_core.a -headers ../apple/include \
  -library tvos-sim/libtruehd_decoder_core.a    -headers ../apple/include \
  -output TrueHDDecoder.xcframework
```

## 4. App side
- Add `TrueHDDecoder.xcframework` to your target.
- Expose `apple/include/truehd_decoder.h` via a bridging header or module map.
- Use `apple/swift/TrueHDDecoder.swift` to decode access units and schedule the
  resulting `AVAudioPCMBuffer` on an `AVAudioPlayerNode`.

## What this does and does NOT give you
- DOES: lossless TrueHD **channel bed** (5.1/7.1) PCM on all 3 platforms,
  on-device, no GPL/LGPL, no decoder you wrote, no AV receiver, no Dolby payment.
- Does NOT (by design): render Dolby Atmos **objects**. Object decoding/rendering
  is covered by live Dolby patents (~2046). Fold objects to the bed, or license
  Dolby for true object rendering. See ../FINDINGS.md.

## Before you ship
- Confirm the real `truehd` crate API and fill the `TODO(api)` in
  `decoder-core/src/lib.rs` (docs: https://crates.io/crates/truehd).
- `cargo tree` to confirm no (L)GPL transitive deps sneak in.
- Patent posture for the lossless bed is well-supported (MLP core patents
  expired ~2017) but not lawyer-certified — get counsel before commercial ship.

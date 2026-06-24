// TrueHDPassthrough.swift  (tvOS 26+)
//
// The ONLY way to play lossless Dolby TrueHD while your app decodes NOTHING and
// bundles NO decoder: hand the untouched TrueHD bitstream to the OS and let an
// external AV receiver decode it. Apple's API for this is
// `AVAudioContentSource.passthrough`:
//   https://developer.apple.com/documentation/avfaudio/avaudiocontentsource/passthrough
//
// Hard costs (unavoidable, by design):
//   * Requires EXTERNAL HARDWARE — an AVR/soundbar performs the decode.
//   * tvOS / Apple TV 4K only. iOS and macOS have no TrueHD bitstream output.
//   * Uses AVPlayer — passthrough is an AVFoundation routing feature; there is
//     no non-AVPlayer passthrough API.
//   * As of tvOS 26 betas, TrueHD format enablement on tvOS may still be
//     pending Apple. Verify on a real Apple TV + AVR before relying on it.
//
// This is a scaffold against the documented symbol. Confirm the exact property
// wiring against the shipping SDK — sections marked VERIFY may move.

#if os(tvOS)
import AVFoundation

public final class TrueHDPassthroughPlayer {
    private let player = AVPlayer()
    private var item: AVPlayerItem?

    public init() {}

    /// Configure the audio session to allow bitstream passthrough to the
    /// connected receiver, then play the asset's untouched TrueHD track.
    public func play(url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback, options: [])
        try session.setActive(true)

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        // VERIFY against SDK: select passthrough as the content source so the OS
        // ships the encoded bitstream to the receiver instead of decoding it.
        // The documented symbol is `AVAudioContentSource.passthrough`; the exact
        // property it is assigned to is what to confirm in the tvOS 26 SDK.
        configurePassthrough(on: item)

        self.item = item
        player.replaceCurrentItem(with: item)
        player.play()
    }

    public func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Passthrough wiring (VERIFY against tvOS 26 SDK)

    private func configurePassthrough(on item: AVPlayerItem) {
        // The intent: route the encoded TrueHD bitstream untouched to the AVR.
        // Apple exposes this via AVAudioContentSource.passthrough. Depending on
        // the final API this is set on the player item's audio configuration or
        // via the audio session route. Pseudocode against the documented symbol:
        //
        //   if #available(tvOS 26.0, *) {
        //       item.audioContentSource = .passthrough   // <- confirm exact property name
        //   }
        //
        // Until the property name is confirmed in your SDK, this method is a
        // placeholder so the file compiles; replace with the real assignment.
        _ = item
    }

    /// Best-effort check that a passthrough-capable route (HDMI -> AVR) is
    /// available. Real availability also depends on the AVR's codec support and
    /// Apple having enabled TrueHD passthrough on the OS.
    public static func passthroughLikelyAvailable() -> Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        return route.outputs.contains { $0.portType == .HDMI }
    }
}
#endif

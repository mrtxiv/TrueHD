// TrueHDPassthrough.swift  (tvOS 26+)  —  AVPlayer REFERENCE PATH (EXCLUDED)
//
// ⚠️ This file uses AVPlayer, which the project's constraints EXCLUDE. It is kept
// only as a reference, because the AVPlayer/AVPlayerItem family is the ONLY route
// anyone has actually shipped tvOS 26 passthrough through so far (Infuse/Plex).
// The active no-AVPlayer path is `TrueHDPassthroughRenderer.swift`. If you ever
// relax "no AVPlayer," this is the most likely-to-actually-work starting point.
//
// CORRECTION: an earlier version of this header claimed Apple's passthrough API
// "is `AVAudioContentSource.passthrough`." That is WRONG — that enum is the
// AVAudioConverter DRC `contentSource` value, not an HDMI bitstream switch (name
// collision). There is no confirmed public developer API for tvOS 26 bitstream
// passthrough yet; the `configurePassthrough` below stays a placeholder.
//
// Hard costs (unavoidable, by design):
//   * Requires EXTERNAL HARDWARE — an AVR/soundbar performs the decode.
//   * tvOS / Apple TV 4K only. iOS and macOS have no TrueHD bitstream output.
//   * As of tvOS 26, the developer enable API is unconfirmed; verify on a real
//     Apple TV + AVR before relying on it.

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

        // UNRESOLVED: no confirmed public API ships the encoded bitstream to the
        // receiver instead of decoding it. Do NOT assume AVAudioContentSource
        // (a DRC enum) does this. Placeholder until Apple documents the switch.
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
        // There is NO confirmed public API for this as of June 2026.
        // `AVAudioContentSource.passthrough` is the AVAudioConverter DRC enum, NOT
        // this switch (name collision) — do not assign it here expecting bitstream
        // output. Player projects tracking the real API are still open feature
        // requests (Swiftfin #1641, KSPlayer #862). This method is a deliberate
        // placeholder so the file compiles; wire the real assignment when Apple
        // documents it. Until then, AVPlayer decodes to PCM/Dolby MAT as usual.
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

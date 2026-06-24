// TrueHDAutoPlayer.swift
//
// One entry point that picks the best legal, no-self-decode path for a TrueHD
// file at runtime, based on what's actually connected:
//
//   * tvOS + HDMI route to an AVR  -> lossless TrueHD passthrough via
//                                     AVSampleBufferAudioRenderer (no AVPlayer,
//                                     no decode, Atmos preserved).
//   * otherwise                    -> AC-3 companion via Apple's codec
//                                     (no decode by you, lossy 5.1, all platforms).
//
// Neither path decodes TrueHD in your app or bundles a TrueHD decoder. The
// difference is forced by hardware: only an external AVR can decode TrueHD
// losslessly, and only tvOS can route the bitstream to it.

import AVFoundation

public enum TrueHDPlaybackOutcome {
    case losslessPassthrough   // TrueHD bitstream -> AVR (tvOS + HDMI)
    case ac3Companion          // AC-3/E-AC-3 via Apple's codec (lossy)
    case unavailable(String)
}

public enum TrueHDAutoPlayer {

    /// True when an HDMI output route is present (a plausible AVR target). Real
    /// passthrough also needs the AVR to support TrueHD and the OS to enable it.
    public static func hdmiRouteAvailable() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .HDMI }
    }

    /// Decide and start playback for `url`. Holds onto whatever player it starts
    /// via the returned objects; keep them alive for the duration of playback.
    @discardableResult
    public static func play(url: URL) -> TrueHDPlaybackOutcome {
        #if os(tvOS)
        if #available(tvOS 26.0, *), hdmiRouteAvailable() {
            if let source = FFmpegTrueHDSource(url: url) {
                let renderer = TrueHDPassthroughRenderer(source: source,
                                                         sampleRate: source.sampleRate,
                                                         channels: source.channels)
                do {
                    try renderer.start()
                    _activeTrueHD = renderer
                    return .losslessPassthrough
                } catch {
                    // fall through to AC-3 companion
                }
            }
        }
        #endif

        // Fallback: AC-3 companion (Apple decodes; works everywhere, no AVR).
        if let pipeline = AC3DecodePipeline.makeWithFFmpeg(url: url) {
            do {
                try pipeline.start()
                _activeAC3 = pipeline
                return .ac3Companion
            } catch {
                return .unavailable("AC-3 pipeline failed to start: \(error)")
            }
        }
        return .unavailable("No TrueHD passthrough route and no AC-3 companion track found.")
    }

    public static func stop() {
        #if os(tvOS)
        _activeTrueHD?.stop(); _activeTrueHD = nil
        #endif
        _activeAC3?.stop(); _activeAC3 = nil
    }

    // Keep started players alive.
    #if os(tvOS)
    private static var _activeTrueHD: TrueHDPassthroughRenderer?
    #endif
    private static var _activeAC3: AC3DecodePipeline?
}

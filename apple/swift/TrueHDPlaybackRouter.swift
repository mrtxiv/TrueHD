// TrueHDPlaybackRouter.swift
//
// Single entry point that picks the best legal, on-device playback path for a
// Dolby TrueHD source on iOS / macOS / tvOS, given a policy. This ties together
// the two tiers already in this repo:
//
//   .ac3Companion -> Apple's own AC-3/E-AC-3 decoder (no decode in your code,
//                    no GPL/LGPL, no license, lossy). See AC3CompanionDecoder.swift.
//   .losslessBed  -> Apache-2.0 truehdd core, decoded on-device (lossless bed,
//                    a bundled non-GPL decoder runs). See ../../decoder-core/.
//
// There is deliberately NO "lossless + no-decode + no-hardware" option, because
// that combination is empty: Apple ships no TrueHD decoder, so something must
// decode. See ../FINDINGS.md. This router makes the trade-off explicit instead
// of pretending it away.

import AVFoundation

public enum TrueHDPlaybackPolicy {
    /// Never bundle a decoder. Apple decodes the AC-3 companion (lossy). If no
    /// companion track exists, playback of that title is unavailable.
    case noDecodeOnly
    /// Prefer lossless via the bundled Apache-2.0 core; fall back to the AC-3
    /// companion when no TrueHD track / decoder is available.
    case losslessPreferred
    /// Lossless only; fail if the bundled core can't handle the stream.
    case losslessOnly
}

public enum TrueHDPlaybackRoute: Equatable {
    case ac3Companion(codec: String)   // "ac-3" or "ec-3"
    case losslessBed                   // truehdd core
    case unavailable(reason: String)
}

public struct TrueHDSource {
    /// Whether the container exposes an AC-3/E-AC-3 companion track Apple can decode.
    public let hasAC3Companion: Bool
    public let companionCodec: String?   // "ac-3" / "ec-3"
    /// Whether a TrueHD elementary stream is present for the bundled core.
    public let hasTrueHDStream: Bool

    public init(hasAC3Companion: Bool, companionCodec: String?, hasTrueHDStream: Bool) {
        self.hasAC3Companion = hasAC3Companion
        self.companionCodec = companionCodec
        self.hasTrueHDStream = hasTrueHDStream
    }
}

public enum TrueHDPlaybackRouter {

    /// Decide the playback route for a source under a policy. Pure function —
    /// no I/O — so it's trivially unit-testable.
    public static func route(for source: TrueHDSource,
                             policy: TrueHDPlaybackPolicy) -> TrueHDPlaybackRoute {
        switch policy {
        case .noDecodeOnly:
            if source.hasAC3Companion {
                return .ac3Companion(codec: source.companionCodec ?? "ac-3")
            }
            return .unavailable(reason:
                "No AC-3/E-AC-3 companion track, and no-decode policy forbids a bundled decoder.")

        case .losslessPreferred:
            if source.hasTrueHDStream {
                return .losslessBed
            }
            if source.hasAC3Companion {
                return .ac3Companion(codec: source.companionCodec ?? "ac-3")
            }
            return .unavailable(reason: "No TrueHD stream and no AC-3 companion present.")

        case .losslessOnly:
            if source.hasTrueHDStream {
                return .losslessBed
            }
            return .unavailable(reason: "No TrueHD stream; lossless-only policy forbids the lossy companion.")
        }
    }

    /// Human-readable note about what the chosen route does and does not give,
    /// so a player UI can be honest with the user (no "lossless" badge on AC-3).
    public static func disclosure(for route: TrueHDPlaybackRoute) -> String {
        switch route {
        case .ac3Companion(let codec):
            let name = codec == "ec-3" ? "Dolby Digital Plus (E-AC-3)" : "Dolby Digital (AC-3)"
            return "Playing the \(name) companion track via the system decoder. Lossy 5.1 — not the lossless TrueHD."
        case .losslessBed:
            return "Playing the lossless TrueHD channel bed via the bundled decoder (RESEARCH-ONLY: TrueHD/MLP decode is patent-uncertain — the bundled crate disclaims production use and Apache-2.0 does not grant Dolby's patents). Atmos objects are not rendered."
        case .unavailable(let reason):
            return "No playable audio path: \(reason)"
        }
    }
}

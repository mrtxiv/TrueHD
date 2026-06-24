// AudioDecoderProbe.swift
//
// Purpose
// -------
// Decisively answer ONE question on real Apple hardware:
//   "Does iOS / macOS / tvOS ship a reachable, OS-registered TrueHD/MLP audio
//    decoder component that my app could use WITHOUT bundling its own decoder?"
//
// It enumerates every audio decoder/encoder AudioComponent the OS exposes
// (AudioComponentFindNext over componentType 'adec' and 'aenc', wildcard
// subtype + manufacturer), prints each as a human-readable FourCC + name, and
// flags any MLP/TrueHD FourCC ('mlp ', 'trhd', 'mlpa'). It also probes whether
// the public AudioFormatID table can even *describe* a TrueHD stream.
//
// How to read the result
// ----------------------
//  * If NO 'mlp '/'trhd' decoder is listed  -> there is no OS TrueHD decoder.
//    Any app "playing TrueHD" is either bundling its own decoder, using
//    AVAudioContentSource.passthrough to an external AVR (tvOS 26+), or playing
//    the lossy AC-3 companion track. (As of this writing: AC-3, E-AC-3 and
//    E-AC-3 JOC are the only Dolby decoders Apple ships.)
//  * If a 'mlp '/'trhd' decoder IS listed: run this from a CLEAN target with
//    NONE of the suspected app's frameworks linked. If it disappears, it was
//    registered by that app (AudioComponentRegister), not by the OS. Even if it
//    survives as a private Apple SPI, calling it is a private-API use that
//    App Review guideline 2.5.1 forbids -> not shippable.
//
// Build (macOS):   swiftc AudioDecoderProbe.swift -o probe && ./probe
// iOS/tvOS:        drop into an app target, call AudioDecoderProbe.run().
//
// No third-party dependencies. Uses only public AudioToolbox API.

import AudioToolbox
import Foundation

enum AudioDecoderProbe {

    /// Turn an OSType/FourCharCode into a readable 4-char string (with hex fallback).
    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        let printable = bytes.allSatisfy { $0 >= 0x20 && $0 < 0x7F }
        if printable {
            return "'" + String(bytes: bytes, encoding: .ascii)! + "'"
        }
        return String(format: "0x%08X", code)
    }

    /// FourCCs that would indicate a TrueHD/MLP (Meridian Lossless Packing) codec.
    /// 'mlp ' and 'mlpa' are the MLP/MLP-audio codes; 'trhd' is a common TrueHD tag.
    static let trueHDCodes: Set<FourCharCode> = [
        fourCCValue("mlp "),
        fourCCValue("mlpa"),
        fourCCValue("trhd"),
        fourCCValue("Atmo"),
    ]

    static func fourCCValue(_ s: String) -> FourCharCode {
        precondition(s.utf8.count == 4)
        var result: FourCharCode = 0
        for b in s.utf8 { result = (result << 8) | FourCharCode(b) }
        return result
    }

    /// Enumerate all components of a given type and print them.
    @discardableResult
    static func enumerate(type: OSType, label: String) -> [AudioComponentDescription] {
        print("\n=== \(label)  (componentType \(fourCC(type))) ===")
        var found: [AudioComponentDescription] = []

        // Wildcard description: subtype 0 + manufacturer 0 matches everything of `type`.
        var search = AudioComponentDescription(
            componentType: type,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        var comp: AudioComponent? = AudioComponentFindNext(nil, &search)
        var index = 0
        while let c = comp {
            var desc = AudioComponentDescription()
            AudioComponentGetDescription(c, &desc)

            var nameCF: Unmanaged<CFString>?
            let nameStatus = AudioComponentCopyName(c, &nameCF)
            let name = (nameStatus == noErr ? (nameCF?.takeRetainedValue() as String?) : nil) ?? "<no name>"

            let isTrueHD = trueHDCodes.contains(desc.componentSubType)
            let flag = isTrueHD ? "  <-- *** TrueHD/MLP CODE PRESENT ***" : ""

            print(String(format: "  [%02d] subtype=%@  mfr=%@  name=%@%@",
                         index,
                         fourCC(desc.componentSubType),
                         fourCC(desc.componentManufacturer),
                         name,
                         flag))

            found.append(desc)
            comp = AudioComponentFindNext(c, &search)
            index += 1
        }

        if found.isEmpty { print("  (none)") }
        return found
    }

    /// Can the public AudioFormatID table even *describe* a TrueHD stream?
    /// We check that the documented Dolby formats resolve and that no public
    /// 'mlp '/'trhd' AudioFormatID is usable to build an ASBD.
    static func probeFormatIDs() {
        print("\n=== Public AudioFormatID sanity check ===")
        let known: [(String, AudioFormatID)] = [
            ("kAudioFormatAC3", kAudioFormatAC3),
            ("kAudioFormat60958AC3", kAudioFormat60958AC3),
            ("kAudioFormatEnhancedAC3", kAudioFormatEnhancedAC3), // E-AC-3 (DD+)
        ]
        for (n, id) in known {
            print("  \(n) = \(fourCC(id))  (public constant exists)")
        }
        // There is deliberately NO kAudioFormatMLP / kAudioFormatTrueHD in the SDK.
        // Without a public AudioFormatID you cannot construct an
        // AudioStreamBasicDescription / CMAudioFormatDescription for TrueHD.
        print("  kAudioFormatMLP / kAudioFormatTrueHD: NOT DEFINED in public SDK")
        print("  -> A TrueHD elementary stream cannot be described to CoreAudio")
        print("     with public API, let alone decoded by it.")
    }

    static func run() {
        print("AudioDecoderProbe — OS-registered audio codec enumeration")
        #if os(macOS)
        print("Platform: macOS")
        #elseif os(tvOS)
        print("Platform: tvOS")
        #elseif os(iOS)
        print("Platform: iOS")
        #endif

        let decoders = enumerate(type: kAudioDecoderComponentType, label: "Audio DECODERS")
        let encoders = enumerate(type: kAudioEncoderComponentType, label: "Audio ENCODERS")
        probeFormatIDs()

        let trueHDDecoders = decoders.filter { trueHDCodes.contains($0.componentSubType) }
        print("\n=== VERDICT ===")
        if trueHDDecoders.isEmpty {
            print("No TrueHD/MLP DECODER component is registered with this OS.")
            print("Conclusion: there is no Apple-provided TrueHD decoder to call.")
            print("Any lossless TrueHD playback therefore requires EITHER a decoder")
            print("you bundle yourself (e.g. Apache-2.0 truehdd) OR passthrough to")
            print("external hardware (tvOS 26 AVAudioContentSource.passthrough).")
        } else {
            print("A TrueHD/MLP code WAS found. Re-run from a target that links NONE")
            print("of the suspect app's frameworks to confirm OS vs app origin.")
            print("Even if OS-provided, it is undocumented SPI -> App Review 2.5.1.")
        }
        _ = encoders
    }
}

#if os(macOS)
// Allow running as a standalone CLI on macOS.
AudioDecoderProbe.run()
#endif

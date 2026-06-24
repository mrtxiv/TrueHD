// TrueHDPassthroughRenderer.swift  (tvOS 26+)
//
// The breakthrough path: play LOSSLESS Dolby TrueHD with NO AVPlayer and NO
// decoding in your app, by enqueueing the untouched compressed TrueHD bitstream
// to AVSampleBufferAudioRenderer (which accepts compressed buffers) and letting
// tvOS passthrough route it over HDMI to an AV receiver that decodes.
//
// Building blocks (tvOS 26):
//   * AVSampleBufferAudioRenderer + AVSampleBufferRenderSynchronizer (no AVPlayer)
//   * AudioCodecContentSource passthrough: kAudioCodecContentSource_Passthrough /
//     _ApplePassthrough, and AVAudioContentSource.passthrough.
//
// Hard limits (unavoidable):
//   * Needs an external AVR/soundbar over HDMI (it decodes; the app does not).
//   * tvOS only.
//   * Over AirPlay/HomePod, compressed passthrough is SILENT (per Rivulet's
//     real-world note) — you must decode to PCM for those routes instead.
//
// The passthrough-enable call is marked VERIFY: no complete public example
// exists yet (Swiftfin #1641 / KSPlayer #862 are open feature requests). The
// CMSampleBuffer construction and renderer wiring below are final.

#if os(tvOS)
import AVFoundation
import AudioToolbox
import CoreMedia

public protocol TrueHDPacketSource: AnyObject {
    /// Next TrueHD access unit + its presentation time, or nil at end of stream.
    func nextPacket() -> (data: Data, pts: CMTime)?
}

public final class TrueHDPassthroughRenderer {
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let source: TrueHDPacketSource
    private let sampleRate: Double
    private let channels: UInt32
    private var formatDescription: CMAudioFormatDescription?
    private let feedQueue = DispatchQueue(label: "truehd.passthrough.feed")

    public init(source: TrueHDPacketSource, sampleRate: Double = 48_000, channels: UInt32 = 8) {
        self.source = source
        self.sampleRate = sampleRate
        self.channels = channels
        synchronizer.addRenderer(renderer)
    }

    public func start() throws {
        formatDescription = try makeMLPFormatDescription()
        configurePassthrough()   // VERIFY against tvOS 26 SDK (see below)

        renderer.requestMediaDataWhenReady(on: feedQueue) { [weak self] in
            guard let self else { return }
            while self.renderer.isReadyForMoreMediaData {
                guard let (data, pts) = self.source.nextPacket(),
                      let sb = self.makeSampleBuffer(data: data, pts: pts) else {
                    self.renderer.stopRequestingMediaData()
                    return
                }
                self.renderer.enqueue(sb)
            }
        }
        synchronizer.rate = 1.0
    }

    public func stop() {
        renderer.stopRequestingMediaData()
        renderer.flush()
        synchronizer.rate = 0
    }

    // MARK: - Passthrough enable (UNRESOLVED — no public API confirmed yet)

    private func configurePassthrough() {
        // HONEST STATUS (June 2026): there is NO confirmed public developer API
        // to enable tvOS 26 HDMI bitstream passthrough from a hand-built renderer.
        //
        // DO NOT rely on `AVAudioContentSource.passthrough` /
        // `kAudioCodecContentSource_Passthrough` for this: that enum is the
        // `contentSource` value for AVAudioConverter's Dynamic Range Compression
        // (DRC) behavior, NOT an HDMI bitstream switch. It is a name collision.
        //
        // What is actually true:
        //   * tvOS 26 DOES add HDMI bitstream passthrough (TrueHD / DTS-HD MA
        //     untouched to an AVR) — but it is system/route gated and, as of now,
        //     only demonstrated through the AVPlayer/AVPlayerItem family. Player
        //     projects tracking the developer API are still OPEN feature requests
        //     with no working sample (Swiftfin #1641, KSPlayer #862).
        //   * Whether AVSampleBufferAudioRenderer can be told to pass a compressed
        //     'mlpa' bitstream straight to HDMI is UNVERIFIED. Treat this whole
        //     no-AVPlayer lossless path as EXPERIMENTAL until proven on-device.
        //
        // Minimum sanity check we CAN do today: confirm the output route is HDMI.
        // Over AirPlay/HomePod the compressed path is silently dropped regardless.
        let hasHDMI = AVAudioSession.sharedInstance().currentRoute.outputs
            .contains { $0.portType == .HDMI }
        if !hasHDMI {
            // No AVR over HDMI -> passthrough cannot work; caller should fall back
            // to the AC-3 demux path. (TrueHDAutoPlayer already does this.)
            NSLog("[TrueHDPassthrough] No HDMI output route; passthrough unavailable.")
        }
    }

    // MARK: - Format description ('mlpa') + CMSampleBuffer

    private func makeMLPFormatDescription() throws -> CMAudioFormatDescription {
        // 'mlpa' is the MLP/TrueHD FourCC. There is no public kAudioFormat
        // constant, so set mFormatID to the FourCC value directly.
        let mlpa: AudioFormatID = 0x6D6C7061 // 'm''l''p''a'
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: mlpa,
            mFormatFlags: 0,
            mBytesPerPacket: 0,   // compressed, variable
            mFramesPerPacket: 0,  // variable per access unit
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0)
        var fd: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &fd)
        guard status == noErr, let fd else {
            throw NSError(domain: "TrueHDPassthrough", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "CMAudioFormatDescriptionCreate failed"])
        }
        return fd
    }

    private func makeSampleBuffer(data: Data, pts: CMTime) -> CMSampleBuffer? {
        guard let formatDescription else { return nil }

        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,                 // allocate
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0, dataLength: data.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer)
        guard status == kCMBlockBufferNoErr, let bb = blockBuffer else { return nil }

        let copied = data.withUnsafeBytes { raw -> OSStatus in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: bb,
                                          offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sampleSize = data.count
        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer)
        return status == noErr ? sampleBuffer : nil
    }
}
#endif

import CoreVideo
import Foundation
import Metal
import Testing
@testable import XFrame

@Test func sceneCutDetectionDistinguishesCutsFromMotion() throws {
    func filled(_ value: UInt8) throws -> LumaFingerprint {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 128, 72,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]] as CFDictionary,
            &pb
        )
        #expect(status == kCVReturnSuccess)
        let buffer = try #require(pb)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
            memset(base, Int32(value), CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) * CVPixelBufferGetHeightOfPlane(buffer, 0))
        }
        return try #require(LumaFingerprint.capture(from: buffer))
    }

    let dark = try filled(20)
    let slightlyBrighter = try filled(35)
    let flash = try filled(210)
    #expect(!slightlyBrighter.isSceneCut(from: dark))
    #expect(flash.isSceneCut(from: dark))
}

@Test func recentlyPlayedStoreOrdersMostRecentFirstAndFiltersQuery() throws {
    let suite = "XFrameTests.Recent.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RecentlyPlayedStore(defaults: defaults)
    var recent = store.load()
    #expect(recent.isEmpty)
    recent = store.record("B", existing: recent)
    recent = store.record("A", existing: recent)
    recent = store.record("B", existing: recent)
    #expect(recent == ["B", "A"])
    #expect(store.load() == ["B", "A"])

    let games = [
        CloudGame(id: "A", name: "Alpha", productID: nil, access: .init(entitled: true)),
        CloudGame(id: "B", name: "Beta", productID: nil, access: .init(entitled: true)),
        CloudGame(id: "C", name: "Gamma", productID: nil, access: .init(entitled: true)),
    ]
    var query = GameLibraryQuery()
    query.recentlyPlayedOnly = true
    let page = query.page(in: games, favorites: [], recentlyPlayed: recent)
    #expect(page.games.map(\.id) == ["B", "A"])
}

@Test func sdpBitrateAppliesOnlyToVideoSection() {
    let sdp = [
        "v=0",
        "m=audio 9 UDP/TLS/RTP/SAVPF 111",
        "c=IN IP4 0.0.0.0",
        "m=video 9 UDP/TLS/RTP/SAVPF 96",
        "c=IN IP4 0.0.0.0",
        "b=AS:10000",
        "a=rtpmap:96 H264/90000"
    ].joined(separator: "\r\n")

    let updated = SDPBitrate.apply(sdp: sdp, maxMbps: 20)
    #expect(updated.contains("b=AS:20000\r\nb=TIAS:20000000"))
    #expect(!updated.contains("b=AS:10000"))
    let audioPart = updated.components(separatedBy: "m=video")[0]
    #expect(!audioPart.contains("b=AS:"))
}

@Test func fsr1ScalingPlanAndShadersCompile() throws {
    let plan = ScalingPlan.make(mode: .fsr1, source: .init(width: 1920, height: 1080),
                                canvas: .init(width: 3840, height: 2160), fullscreen: false, supported: false)
    #expect(plan.status.effective == .fsr1)
    #expect(plan.status.bypass == nil)
    #expect(OriginalPresenter.effectiveLead(baseLead: 0.003, scalingMode: .fsr1, metalFXGpuEMA: 0.003) > 0.003)

    let sameSize = ScalingPlan.make(mode: .fsr1, source: .init(width: 1920, height: 1080),
                                    canvas: .init(width: 1920, height: 1080), fullscreen: false, supported: true)
    #expect(sameSize.status.effective == .original && sameSize.status.bypass == .noEnlargement)

    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/XFrame/Shaders.metal"), encoding: .utf8)
    let library = try device.makeLibrary(source: source, options: nil)
    #expect(library.makeFunction(name: "fsr1EasuVideoFragment") != nil)
    #expect(library.makeFunction(name: "fsr1RcasFragment") != nil)
}

@Test func multiControllerPacketIndexAndRumbleIndex() throws {
    let packet = try GamepadPacketEncoder.encode(GamepadSnapshot(buttons: [.a]), sequence: 1, timestampMS: 10, gamepadIndex: 2)
    #expect(packet[15] == 2)

    var rumbleBytes: [UInt8] = [0x80, 0x00, 0x00, 0x02, 50, 25, 0, 0, 0xF4, 0x01, 0, 0, 0]
    let cmd = try #require(RumbleCommand.parse(Data(rumbleBytes)))
    #expect(cmd.gamepadIndex == 2)
    #expect(cmd.strong == 0.5 && cmd.weak == 0.25)

    rumbleBytes[3] = 4 // Out of 0..3 range rejected
    #expect(RumbleCommand.parse(Data(rumbleBytes)) == nil)
}

@Test func connectingStatusDotsAnimateAndModesCycle() {
    let t0 = Date(timeIntervalSinceReferenceDate: 0.0)
    let t1 = Date(timeIntervalSinceReferenceDate: 0.46)
    let t2 = Date(timeIntervalSinceReferenceDate: 0.92)
    let t3 = Date(timeIntervalSinceReferenceDate: 1.38)
    #expect(StreamConnectingView.animatedText("Negotiating H.264 video…", at: t0) == "Negotiating H.264 video.")
    #expect(StreamConnectingView.animatedText("Negotiating H.264 video…", at: t1) == "Negotiating H.264 video..")
    #expect(StreamConnectingView.animatedText("Negotiating H.264 video…", at: t2) == "Negotiating H.264 video...")
    #expect(StreamConnectingView.animatedText("Negotiating H.264 video…", at: t3) == "Negotiating H.264 video.")

    #expect(VideoScalingMode.original.next == .integer)
    #expect(VideoScalingMode.fsr1.next == .original)
    #expect(FrameGenerationMode.off.next == .balanced)
    #expect(FrameGenerationMode.quality.next == .off)
}

@Test func sdpResolutionCapRestrictsOnlyH264VideoTo1080p() {
    #expect(CloudStreamQuality.standard.maxMacroblocksPerFrame == 8160)
    #expect(CloudStreamQuality.standard.maxMacroblocksPerSecond == 489_600)
    #expect(!CloudStreamQuality.standard.supportsCustomResolution)
    #expect(CloudStreamQuality.hq.maxMacroblocksPerFrame == nil)
    #expect(CloudStreamQuality.hq.supportsCustomResolution)

    let sdp = [
        "v=0",
        "m=audio 9 UDP/TLS/RTP/SAVPF 111",
        "a=rtpmap:111 opus/48000/2",
        "a=fmtp:111 minptime=10;useinbandfec=1",
        "m=video 9 UDP/TLS/RTP/SAVPF 96 98",
        "a=rtpmap:96 H264/90000",
        "a=fmtp:96 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f;max-fs=14400",
        "a=rtpmap:98 VP9/90000",
        "a=fmtp:98 profile-id=0"
    ].joined(separator: "\r\n")

    let capped = SDPResolutionCap.apply(sdp: sdp, maxFS: 8160, maxMBPS: 489_600)
    #expect(capped.contains("a=fmtp:96 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f;max-fs=8160;max-mbps=489600"))
    #expect(!capped.contains("max-fs=14400"))
    #expect(capped.contains("a=fmtp:98 profile-id=0"))
    #expect(capped.contains("a=fmtp:111 minptime=10;useinbandfec=1"))
}

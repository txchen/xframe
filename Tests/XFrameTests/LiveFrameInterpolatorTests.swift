import CoreVideo
import Foundation
import Metal
import Testing
@testable import XFrame

private func makeDummyNV12Buffer(width: Int, height: Int) throws -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault, width, height,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        attrs as CFDictionary, &pb
    )
    #expect(status == kCVReturnSuccess)
    return try #require(pb)
}

private func makeDummyTexture(width: Int, height: Int) throws -> any MTLTexture {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
    return try #require(device.makeTexture(descriptor: desc))
}

@Test func frameGenerationModeMapsResolutionsAndPersists() {
    let suite = UserDefaults(suiteName: "xframe.fg.mode.test.\(UUID().uuidString)")!
    #expect(FrameGenerationMode.load(suite) == .off)
    FrameGenerationMode.balanced.save(suite)
    #expect(FrameGenerationMode.load(suite) == .balanced)
    #expect(FrameGenerationMode.off.profile(width: 1920, height: 1080) == nil)
    #expect(FrameGenerationMode.balanced.profile(width: 1920, height: 1080) == .p1080Balanced)
    #expect(FrameGenerationMode.quality.profile(width: 1920, height: 1080) == .p1080Quality)
    #expect(FrameGenerationMode.balanced.profile(width: 2560, height: 1440) == .p1440Balanced)
    #expect(FrameGenerationMode.quality.profile(width: 2560, height: 1440) == .p1440Quality)
    #expect(FrameGenerationMode.balanced.profile(width: 1280, height: 720) == .p720)
    #expect(FrameGenerationMode.balanced.profile(width: 800, height: 600) == nil)
}

@Test func schedulerEnforcesMonotonicOrderAndBypasses60FPS() throws {
    var scheduler = FrameInterpolationScheduler()
    scheduler.setMode(.balanced)

    let pbA = try makeDummyNV12Buffer(width: 1920, height: 1080)
    let pbB = try makeDummyNV12Buffer(width: 1920, height: 1080)
    let pbC = try makeDummyNV12Buffer(width: 1920, height: 1080)
    let frameA = VideoFrame(buffer: pbA, time: 0.000, id: 1)
    let frameB = VideoFrame(buffer: pbB, time: 0.0333, id: 2)
    let frameC = VideoFrame(buffer: pbC, time: 0.0500, id: 3) // 16.7 ms after B (60 fps)

    // Frame A arrives: displayed immediately, no job yet.
    let resA = scheduler.ingest(frame: frameA, at: 1.000, isLive: false, width: 1920, height: 1080)
    if case .real(let f) = resA.immediate { #expect(f.id == 1) } else { Issue.record("Expected frame A immediately") }
    #expect(resA.job == nil)

    // Frame B arrives 33.3 ms later: held while mid(A,B) computes.
    let resB = scheduler.ingest(frame: frameB, at: 1.0333, isLive: false, width: 1920, height: 1080)
    #expect(resB.immediate == nil)
    let jobB = try #require(resB.job)
    #expect(jobB.previous.id == 1 && jobB.current.id == 2 && jobB.profile == .p1080Balanced)

    // Complete mid(A,B) before next display tick.
    let midTex = try makeDummyTexture(width: 1920, height: 1080)
    scheduler.complete(generation: jobB.generation, texture: midTex, width: 1920, height: 1080)

    // First poll delivers mid(A,B), second poll delivers real frame B (monotonic order!).
    let poll1 = scheduler.pollDisplay(at: 1.050)
    if case .interpolated(_, let w, let h, let src) = poll1 {
        #expect(w == 1920 && h == 1080 && src.id == 2)
    } else {
        Issue.record("Expected interpolated midpoint before real frame B")
    }
    let poll2 = scheduler.pollDisplay(at: 1.066)
    if case .real(let f) = poll2 { #expect(f.id == 2) } else { Issue.record("Expected real frame B after midpoint") }

    // Frame C arrives 16.7 ms after B (60 fps stream): must bypass interpolation immediately.
    let resC = scheduler.ingest(frame: frameC, at: 1.083, isLive: false, width: 1920, height: 1080)
    if case .real(let f) = resC.immediate { #expect(f.id == 3) } else { Issue.record("Expected 60 fps frame C to pass through") }
    #expect(resC.job == nil)
}

@Test func schedulerFallsBackToRealFrameOnTimeout() throws {
    var scheduler = FrameInterpolationScheduler()
    scheduler.setMode(.balanced)

    let pbA = try makeDummyNV12Buffer(width: 1920, height: 1080)
    let pbB = try makeDummyNV12Buffer(width: 1920, height: 1080)
    _ = scheduler.ingest(frame: VideoFrame(buffer: pbA, time: 0.0, id: 1), at: 1.0, isLive: false, width: 1920, height: 1080)
    let resB = scheduler.ingest(frame: VideoFrame(buffer: pbB, time: 0.0333, id: 2), at: 1.0333, isLive: false, width: 1920, height: 1080)
    let job = try #require(resB.job)

    // Before timeout: still waiting.
    #expect(scheduler.pollDisplay(at: 1.045) == nil)
    // After 28 ms timeout: releases real frame B and abandons late job.
    let fallback = scheduler.pollDisplay(at: 1.065)
    if case .real(let f) = fallback { #expect(f.id == 2) } else { Issue.record("Expected timeout fallback to real frame B") }
    #expect(scheduler.skippedInterpolations == 1)

    // Late completion from abandoned job must be ignored.
    let lateTex = try makeDummyTexture(width: 1920, height: 1080)
    scheduler.complete(generation: job.generation, texture: lateTex, width: 1920, height: 1080)
    #expect(scheduler.pollDisplay(at: 1.070) == nil)
}

@Test func schedulerPacesRealFrameOn120HzDisplay() throws {
    var scheduler = FrameInterpolationScheduler()
    scheduler.setMode(.balanced)

    let pbA = try makeDummyNV12Buffer(width: 1920, height: 1080)
    let pbB = try makeDummyNV12Buffer(width: 1920, height: 1080)
    _ = scheduler.ingest(frame: VideoFrame(buffer: pbA, time: 0.0, id: 1), at: 1.0, isLive: false, width: 1920, height: 1080)
    let resB = scheduler.ingest(frame: VideoFrame(buffer: pbB, time: 0.0333, id: 2), at: 1.0333, isLive: false, width: 1920, height: 1080)
    let job = try #require(resB.job)
    let midTex = try makeDummyTexture(width: 1920, height: 1080)
    scheduler.complete(generation: job.generation, texture: midTex, width: 1920, height: 1080)

    // Midpoint delivered at t = 1.0416 (first 120 Hz tick after completion).
    if case .interpolated = scheduler.pollDisplay(at: 1.0416) {} else { Issue.record("Expected midpoint") }
    // Next 120 Hz tick (+8.3 ms = 1.0500) must wait instead of emitting real frame immediately (no 1-1-0-0 judder).
    #expect(scheduler.pollDisplay(at: 1.0500) == nil)
    // Following 120 Hz tick (+16.7 ms = 1.0583) releases real frame B.
    if case .real(let f) = scheduler.pollDisplay(at: 1.0583) { #expect(f.id == 2) } else { Issue.record("Expected paced real frame B") }
}

@Test func lumaFingerprintDetectsDuplicateAndChangedFrames() throws {
    let pb1 = try makeDummyNV12Buffer(width: 1280, height: 720)
    let pb2 = try makeDummyNV12Buffer(width: 1280, height: 720)
    let pb3 = try makeDummyNV12Buffer(width: 1280, height: 720)

    func fillY(_ pb: CVPixelBuffer, value: UInt8) {
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        if let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) {
            let bytes = CVPixelBufferGetBytesPerRowOfPlane(pb, 0) * CVPixelBufferGetHeightOfPlane(pb, 0)
            memset(base, Int32(value), bytes)
        }
    }
    fillY(pb1, value: 40)
    fillY(pb2, value: 40)
    fillY(pb3, value: 180)

    let fp1 = try #require(LumaFingerprint.capture(from: pb1))
    let fp2 = try #require(LumaFingerprint.capture(from: pb2))
    let fp3 = try #require(LumaFingerprint.capture(from: pb3))
    #expect(fp1.isNearlyIdentical(to: fp2))
    #expect(!fp1.isNearlyIdentical(to: fp3))
}

@Test func liveInterpolatorProducesInterpolatedTextureWhenWeightsCached() async throws {
    guard (try? BenchmarkModelCache().cachedModel()) != nil else { return }
    let device = try #require(MTLCreateSystemDefaultDevice())
    let interpolator = LiveFrameInterpolator(device: device, resourceBundle: Bundle.module)
    interpolator.setMode(.balanced)

    let pbA = try makeDummyNV12Buffer(width: 1920, height: 1080)
    let pbB = try makeDummyNV12Buffer(width: 1920, height: 1080)
    let outA = interpolator.ingest(frame: VideoFrame(buffer: pbA, time: 0.0, id: 1), at: 1.0, isLive: false)
    #expect(outA != nil)
    let outB = interpolator.ingest(frame: VideoFrame(buffer: pbB, time: 0.0333, id: 2), at: 1.0333, isLive: false)
    #expect(outB == nil)

    // Wait up to 3 seconds (allows first-time compilation if needed) for async interpolation.
    var gotInterpolated = false
    for _ in 0..<60 {
        if let polled = interpolator.pollDisplay(at: 1.040) {
            if case .interpolated(let box, let w, let h, _) = polled {
                #expect(box.texture.width == 1920 && box.texture.height == 1080 && w == 1920 && h == 1080)
                gotInterpolated = true
                break
            }
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(gotInterpolated)
}

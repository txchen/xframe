import Foundation
import CoreVideo
import Metal
import QuartzCore
import Testing
import WebRTC
@testable import XFrame

// MARK: VSync selection on a virtual clock (independent reference = simulated refresh grid, not the lattice itself)

private struct Sim {
    var refreshes: [Double]                       // reference refresh times
    var sampleOffset: [Int: Double] = [:]         // refresh index -> timestamp offset of its display-link sample
    var dropped: Set<Int> = []                    // refresh indices whose display-link sample is lost
    let lead = 0.003
    /// Runs the worker loop (wake at v - lead, submit 0.3 ms later). Returns (submit time, index of the reference
    /// refresh the submit can make, target v) per submit.
    func run(until end: Double) -> [(submit: Double, refresh: Int, v: Double)] {
        let lattice = VsyncLattice(); var si = 0; var now = refreshes[0] + 0.0001; var lastSubmit = 0.0; var out: [(Double, Int, Double)] = []
        func deliver(_ t: Double) {
            while si < refreshes.count, refreshes[si] + 0.0006 <= t {
                if !dropped.contains(si) {
                    let ts = refreshes[si] + (sampleOffset[si] ?? 0)
                    let p = si + 1 < refreshes.count ? refreshes[si + 1] - refreshes[si] : 1.0 / 60
                    lattice.update(timestamp: ts, target: ts + p, now: refreshes[si] + 0.0006)
                }
                si += 1
            }
        }
        while now < end {
            deliver(now)
            let (v, age) = VsyncTarget.next(lattice: lattice, now: now, lead: lead, lastSubmit: lastSubmit)
            if v == 0 || age > OriginalPresenter.staleLimit { now += 0.002; continue }
            let wake = max(now, v - lead); deliver(wake)
            let submit = wake + 0.0003
            guard let k = refreshes.firstIndex(where: { $0 >= submit + 0.0005 }) else { break }
            out.append((submit, k, v)); lastSubmit = submit; now = submit + 0.0001
        }
        return out
    }
}

private func grid(_ start: Double, _ end: Double, _ period: Double) -> [Double] {
    var t = start, out: [Double] = []; while t < end { out.append(t); t += period }; return out
}

@Test(arguments: [-0.0035, -0.0043, 0.0065])
func reprojectionRecoversFromOneOffGridSampleAfterACallbackGap(offset: Double) {
    let refreshes = grid(0.1, 6, 1.0 / 60)
    let bad = refreshes.firstIndex { $0 >= 3.0 }!
    var sim = Sim(refreshes: refreshes)
    sim.dropped = Set((bad - 5)..<bad)            // ~83 ms of lost display-link callbacks; hardware keeps refreshing
    sim.sampleOffset[bad] = offset                 // first sample after the gap is off-grid (both signs observed)
    let subs = sim.run(until: 5.8)
    // targets strictly advance and never reuse a reference refresh
    #expect(zip(subs, subs.dropFirst()).allSatisfy { $1.v > $0.v })
    #expect(zip(subs, subs.dropFirst()).allSatisfy { $1.refresh > $0.refresh })
    // no persistent phase offset: from 0.1 s after the bad sample every submit is lead - 0.3 ms before its refresh
    let after = subs.filter { $0.submit > refreshes[bad] + 0.1 }
    #expect(!after.isEmpty)
    #expect(after.allSatisfy { abs((refreshes[$0.refresh] - $0.submit) - 0.0027) < 0.0005 })
}

@Test func reprojectionFollowsARealRefreshRateChange() {
    let refreshes = grid(0.1, 3, 1.0 / 60) + grid(3.0, 6, 0.02)      // 60 Hz -> 50 Hz
    let subs = Sim(refreshes: refreshes).run(until: 5.8)
    #expect(zip(subs, subs.dropFirst()).allSatisfy { $1.refresh > $0.refresh })
    let tail = subs.filter { $0.submit > 3.3 }
    #expect(!tail.isEmpty && tail.allSatisfy { abs((refreshes[$0.refresh] - $0.submit) - 0.0027) < 0.0005 })
}

@Test func workerStopsSubmittingOnStaleDisplayLinkAndResumesAfterResync() {
    var sim = Sim(refreshes: grid(0.1, 6, 1.0 / 60))
    let a = sim.refreshes.firstIndex { $0 >= 2.0 }!, b = sim.refreshes.firstIndex { $0 >= 2.5 }!
    sim.dropped = Set(a..<b)                                           // 500 ms without display-link samples
    let subs = sim.run(until: 5.8)
    let inside = subs.filter { $0.submit > sim.refreshes[a] + OriginalPresenter.staleLimit + 0.02 && $0.submit < sim.refreshes[b] }
    #expect(inside.isEmpty)                                            // bounded: no projection past the stale limit
    #expect(subs.contains { $0.submit > sim.refreshes[b] && $0.submit < sim.refreshes[b] + 0.1 })
}

// MARK: Worker lifecycle on the real Metal/CoreVideo path (offscreen layer, no window or UI)

private func nv12(_ w: Int, _ h: Int) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]]
    #expect(CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes as CFDictionary, &buffer) == kCVReturnSuccess)
    return try #require(buffer)
}

private func pipeline(_ device: any MTLDevice) throws -> any MTLRenderPipelineState {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let library = try device.makeLibrary(source: try String(contentsOf: root.appendingPathComponent("Sources/XFrame/Shaders.metal"), encoding: .utf8), options: nil)
    let d = MTLRenderPipelineDescriptor()
    d.vertexFunction = library.makeFunction(name: "patternVertex"); d.fragmentFunction = library.makeFunction(name: "videoFragment")
    d.colorAttachments[0].pixelFormat = .bgra8Unorm
    return try device.makeRenderPipelineState(descriptor: d)
}

private func acquirePermits(_ s: DispatchSemaphore, _ n: Int, timeout: Double) -> Int {
    var got = 0
    for _ in 0..<n { if s.wait(timeout: .now() + timeout) == .success { got += 1 } }
    for _ in 0..<got { s.signal() }
    return got
}

@Test func workerRendersFollowsResizeParksAndStopsWithoutLeakingPermits() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let layer = CAMetalLayer(); layer.device = device; layer.pixelFormat = .bgra8Unorm; layer.drawableSize = CGSize(width: 64, height: 36)
    let inFlight = DispatchSemaphore(value: 3)
    let presentationQueue = PresentationQueue()
    let worker = try OriginalPresenter(queue: queue, pipeline: try pipeline(device), inFlight: inFlight,
                                       presentationQueue: presentationQueue, layer: layer, device: device)
    let source = LiveVideo()
    worker.configure(source: source)
    #expect(worker.stop())                                             // stopping before start is a no-op
    let worker2 = try OriginalPresenter(queue: queue, pipeline: try pipeline(device), inFlight: inFlight,
                                        presentationQueue: presentationQueue, layer: layer, device: device)
    worker2.configure(source: source); worker2.start(); worker2.start()   // second start ignored
    let feeding = Task.detached {
        var k = 0
        while !Task.isCancelled {
            let now = CACurrentMediaTime(); let ts = (now * 60).rounded(.down) / 60
            worker2.lattice.update(timestamp: ts, target: ts + 1.0 / 60, now: now)
            if k % 2 == 0, let buffer = try? nv12(64, 36) {
                source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: buffer), rotation: ._0, timeStampNs: Int64(k) * 16_666_667))
            }
            k += 1
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
    }
    worker2.setActive(true)
    func wait(_ cond: () -> Bool, _ seconds: Double) async -> Bool {
        let end = CACurrentMediaTime() + seconds
        while CACurrentMediaTime() < end { if cond() { return true }; try? await Task.sleep(nanoseconds: 5_000_000) }
        return cond()
    }
    #expect(await wait({ worker2.lastDrawableSize == CGSize(width: 64, height: 36) }, 2))
    // HUD accounting while the worker draws: draw ticks advance and the scaling status reflects the drawable.
    #expect(await wait({ source.performance.snapshot().pacing.drawTicks > 0 }, 1))
    #expect(worker2.lastScalingStatus?.effective == .original)
    #expect(worker2.timeConstraintApplied != nil)
    layer.drawableSize = CGSize(width: 128, height: 72)                // resize while running
    #expect(await wait({ worker2.lastDrawableSize == CGSize(width: 128, height: 72) }, 2))
    #expect(await wait({ worker2.lastScalingStatus?.output == ScalingExtent(width: 128, height: 72) }, 1))
    #expect(source.performance.snapshot().scaling?.output == ScalingExtent(width: 128, height: 72))
    worker2.setActive(false)
    #expect(await wait({ worker2.isIdle }, 0.2))                      // parks promptly (ownership hand-back precondition)
    // Once parked, the worker submits nothing more while frames keep arriving (no second owner after hand-back).
    let parkedSubmits = source.frameTrace.snapshot().filter { $0.stage == .submitted }.count
    #expect(parkedSubmits > 0)
    try? await Task.sleep(nanoseconds: 150_000_000)
    #expect(source.frameTrace.snapshot().filter { $0.stage == .submitted }.count == parkedSubmits)
    feeding.cancel()
    #expect(worker2.stop())
    #expect(worker2.stop())                                           // idempotent
    // every GPU permit returns once submitted work completes
    #expect(acquirePermits(inFlight, 3, timeout: 1) == 3)
}

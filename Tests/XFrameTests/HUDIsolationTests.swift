import AppKit
import Testing
@testable import XFrame

private func hudFixture() -> PlaybackStats {
    var s = PlaybackStats()
    s.isLive = true
    s.hardware = true
    s.state = "Streaming"
    s.recentDecodedFPS = 60
    s.recentPresentedFPS = 59.8
    s.videoBitrateMbps = 18.7
    s.networkRoundTripMS = 28
    s.jitterBufferMS = 1.2
    s.decoded = 7200
    s.presented = 7176
    s.elapsed = 120
    s.dropped = 24
    s.capacity = 2
    s.videoPacketsLost = 0
    s.videoNacks = 0
    s.timings.gpu = TimingSummary(count: 300, recentCount: 256, meanMS: 0.6, p50MS: 0.5, p95MS: 0.9, maxMS: 1.1)
    return s
}

@Test func hudDocumentHasHonestUnitsAndUnavailableValues() {
    let s = hudFixture()
    let compact = HUDDocument(stats: s, preset: .compact)
    #expect(compact.rows.contains { $0.name == "Output · 2s" && $0.value == "59.8 fps" })
    #expect(compact.rows.contains { $0.name == "Net + client · est." && $0.value == "—" })
    #expect(compact.accessibilityText.contains("Latency est."))
    #expect(HUDDocument(stats: s, preset: .detailed).rows.count > compact.rows.count)
    #expect(HUDDocument(stats: s, preset: .hidden).rows.isEmpty)
    var invalid = s
    invalid.recentPresentedFPS = .nan
    #expect(HUDDocument(stats: invalid, preset: .compact).outputFPS == nil)
}

@Test func hudHistoryIsBoundedAndDoesNotInventMissingSamples() {
    var history = HUDHistory()
    for i in 0..<500 {
        history.append(HUDDocument(stats: hudFixture(), preset: .compact, sampledAt: Double(i) / 2))
    }
    #expect(history.points.count <= 64)
    #expect(history.points.first!.time >= 249.5 - 30)
    let count = history.points.count
    history.append(HUDDocument(stats: hudFixture(), preset: .compact, sampledAt: 0))
    #expect(history.points.count == count)
    var missing = hudFixture()
    missing.recentPresentedFPS = nil
    history.append(HUDDocument(stats: missing, preset: .compact, sampledAt: 300))
    #expect(history.points.isEmpty)
}

private final class HUDCollectionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let release = DispatchSemaphore(value: 0)
    var calls: Int { lock.withLock { count } }
    func collect() -> HUDDocument {
        lock.withLock { count += 1 }
        _ = release.wait(timeout: .now() + 5)
        return HUDDocument(stats: hudFixture(), preset: .compact)
    }
}

@Test @MainActor func slowHUDCollectionDoesNotBlockMediaOrDeliverAfterStop() async throws {
    let sampler = HUDSampler()
    let gate = HUDCollectionGate()
    var deliveries = 0
    sampler.start(collect: { gate.collect() }, deliver: { _ in deliveries += 1 })
    for _ in 0..<100 where gate.calls == 0 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(gate.calls == 1)
    // Main actor and media state remain usable while the collector is held.
    let video = LiveVideo()
    video.setRecovering(true)
    #expect(video.snapshot().connectionRecovering)
    #expect(gate.calls == 1)
    sampler.stop()
    gate.release.signal()
    try await Task.sleep(for: .milliseconds(100))
    #expect(deliveries == 0)
    sampler.start(collect: { HUDDocument(stats: hudFixture(), preset: .compact) },
                  deliver: { _ in deliveries += 1 })
    for _ in 0..<100 where deliveries == 0 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(deliveries == 1)
    sampler.stop()
}

@Test func diagnosticSnapshotsRemainConsistentDuringConcurrentWrites() async {
    let performance = PlaybackPerformance()
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            for _ in 0..<2000 { performance.record(.gpu, seconds: 0.001) }
        }
        group.addTask {
            for _ in 0..<100 {
                if let summary = performance.snapshot().gpu {
                    #expect(summary.recentCount <= 256)
                    #expect(summary.p95MS == 1)
                }
            }
        }
    }
    #expect(performance.snapshot().gpu?.count == 2000)
}

@Test @MainActor func hudPaintsCompactAndDetailedPreviews() throws {
    _ = NSApplication.shared
    for preset in [PerformanceHUDPreset.compact, .detailed] {
        let view = PerformanceHUDView()
        view.preset = preset
        view.frame = NSRect(origin: .zero, size: view.intrinsicContentSize)
        for i in 0..<60 {
            var stats = hudFixture()
            stats.recentPresentedFPS = i == 40 ? 54 : 59.8
            view.update(HUDDocument(stats: stats, preset: preset, sampledAt: Double(i) / 2), controller: "Xbox", quality: .hq)
        }
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/hud-\(preset.rawValue)-preview.png")
        try png.write(to: path)
        #expect(!png.isEmpty)
        view.preset = .hidden
        #expect(view.isHidden)
    }
}

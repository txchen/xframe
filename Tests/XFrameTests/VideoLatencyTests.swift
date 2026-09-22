import Foundation
import Testing
@testable import XFrame

@Test func jitterBufferLatencyUsesIntervalCountersAndRejectsResets() {
    var meter = VideoLatencyMeter()
    #expect(meter.sample(id: "a", timestampUS: 1_000_000, delay: 3, count: 100) == nil)
    #expect(meter.sample(id: "a", timestampUS: 2_000_000, delay: 4.2, count: 160).map { abs($0 - 20) < 0.001 } == true)
    #expect(meter.sample(id: "a", timestampUS: 2_000_000, delay: 5, count: 200) == nil)
    #expect(meter.sample(id: "a", timestampUS: 3_000_000, delay: 4.2, count: 160) == nil)
    #expect(meter.sample(id: "b", timestampUS: 4_000_000, delay: 7, count: 300) == nil)
    #expect(meter.sample(id: "b", timestampUS: 5_000_000, delay: 0, count: 0) == nil)
    #expect(meter.sample(id: "b", timestampUS: 6_000_000, delay: 0.5, count: 50) == 10)
    #expect(meter.sample(id: "b", timestampUS: 7_000_000, delay: .nan, count: 50) == nil)
}

@Test func latencyEstimateRequiresAllPartsAndUsesMeansWithoutDoubleCountingWait() {
    var stats = PlaybackStats()
    stats.networkRoundTripMS = 20
    stats.jitterBufferMS = 10
    #expect(stats.pipelineLatencyEstimateMS == nil)
    stats.timings.decode = TimingSummary(count: 1, recentCount: 1, meanMS: 3, p50MS: 3, p95MS: 8, maxMS: 8)
    stats.timings.presentation = TimingSummary(count: 1, recentCount: 1, meanMS: 30, p50MS: 30, p95MS: 50, maxMS: 50)
    stats.timings.frameWait = TimingSummary(count: 1, recentCount: 1, meanMS: 12, p50MS: 12, p95MS: 20, maxMS: 20)
    #expect(stats.pipelineLatencyEstimateMS == 63) // Presentation already includes local frame waiting/GPU.
    stats.isLive = true
    let detailed = PerformanceHUDText.render(stats, preset: .detailed, controller: "", quality: .hq)
    #expect(detailed.contains("HQ requested") && detailed.contains("Latency est. 63.0 ms"))
    #expect(detailed.contains("host delay not measured"))
    #expect(PerformanceHUDText.render(stats, preset: .compact, controller: "", quality: .standard).contains("SQ requested"))
    stats.networkRoundTripMS = .infinity
    #expect(stats.pipelineLatencyEstimateMS == nil)
}

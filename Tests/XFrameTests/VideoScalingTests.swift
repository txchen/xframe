import Testing
@testable import XFrame

@Test func scalingUsesPicturePixelsAndTemporaryBypass() {
    let source = ScalingExtent(width: 1920, height: 1080)
    func plan(_ mode: VideoScalingMode, _ w: Int, _ h: Int, fullscreen: Bool = true, supported: Bool = true) -> ScalingPlan {
        ScalingPlan.make(mode: mode, source: source, canvas: .init(width: w, height: h), fullscreen: fullscreen, supported: supported)
    }
    let full = plan(.metalFX, 3840, 2160)
    #expect(full.status.effective == .metalFX)
    #expect(full.status.output == ScalingExtent(width: 3840, height: 2160))
    let window = plan(.metalFX, 3840, 2036, fullscreen: false)
    #expect(window.status.output.height == 2036 && window.status.output.width == 3620)
    #expect(window.x > 0 && abs(window.y) < 0.000001)
    #expect(plan(.metalFX, 1920, 1080).status.bypass == .noEnlargement)
    #expect(plan(.metalFX, 960, 540).status.effective == .original)
    #expect(plan(.metalFX, 3840, 2160, supported: false).status.bypass == .unsupported)
    #expect(plan(.integer, 3840, 2160).status.effective == .integer)
    #expect(plan(.integer, 3840, 2160, fullscreen: false).status.bypass == .windowed)
    #expect(plan(.integer, 3840, 2036).status.bypass == .nonInteger)
    #expect(plan(.integer, 3840, 2160, supported: false).status.effective == .integer)
    let oddBars = plan(.integer, 3841, 2160)
    #expect(oddBars.status.effective == .integer && oddBars.x == 0 && oddBars.y == 0)
    #expect(plan(.original, 3840, 2160).status.bypass == nil)
}

@Test func scalingMetricsRejectRetiredConfigurations() {
    let metrics = PlaybackPerformance()
    let plan = ScalingPlan.make(mode: .metalFX, source: .init(width: 1920, height: 1080),
        canvas: .init(width: 3840, height: 2160), fullscreen: true, supported: true)
    let revision = metrics.setScaling(plan.status)
    metrics.recordScaler(seconds: 0.002, revision: revision)
    #expect(metrics.snapshot().scaler?.meanMS == 2)
    #expect(metrics.setScaling(plan.status) == revision)
    var bypass = plan.status
    bypass.effective = .original; bypass.bypass = .initializationFailed
    metrics.setScaling(bypass)
    metrics.recordScaler(seconds: 0.010, revision: revision)
    #expect(metrics.snapshot().scaler == nil)
    #expect(metrics.snapshot().scaling == bypass)
    #expect(metrics.setScaling(plan.status) != revision)
    metrics.recordScaler(seconds: 0.010, revision: revision)
    #expect(metrics.snapshot().scaler == nil)
}

@Test func diagnosticReportIncludesSelectedAndEffectiveScaling() throws {
    let metrics = PlaybackPerformance()
    let status = ScalingPlan.make(mode: .integer, source: .init(width: 1920, height: 1080),
        canvas: .init(width: 2560, height: 1440), fullscreen: false, supported: true).status
    metrics.setScaling(status)
    var stats = PlaybackStats()
    stats.timings = metrics.snapshot()
    let report = StreamDiagnosticReport(stats: stats, outcome: .active, duration: 1, events: [])
    #expect(report.timings.scaling?.selected == .integer)
    #expect(report.timings.scaling?.effective == .original)
    #expect(report.timings.scaling?.bypass == .windowed)
    #expect(report.timings.scaler == nil)
    #expect(try !report.encoded().isEmpty)
}

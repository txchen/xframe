import Foundation
import Testing
@testable import XFrame

@Test func benchmarkGradesUseTheMeasuredP95() {
    #expect(BenchmarkGrade.assess(p95MS: 7, budgetMS: 10) == .headroom)
    #expect(BenchmarkGrade.assess(p95MS: 8, budgetMS: 10) == .tight)
    #expect(BenchmarkGrade.assess(p95MS: 11, budgetMS: 10) == .overBudget)
    let result = BenchmarkMeasurement.measured("example", "Example", detail: "", timing: "GPU",
        values: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], budgetMS: 10)
    #expect(result.p95MS == 10 && result.grade == .tight)
    let report = PostProcessingBenchmarkReport(date: .now, device: "Test", macOS: "Test", fixture: "Test",
        measurements: [result], notes: [])
    #expect(report.capacitySummary.contains("No tested frame-generation tier"))
}

@Test func bundledBenchmarkExecutesItsAvailableBackends() async throws {
    let report = try await PostProcessingBenchmark.run(progress: { _ in })
    #expect(report.measurements.map(\.id) == ["spatial1440", "spatial4k", "spatial4kSharpen", "vt720", "vt1080", "vt1440"])
    for measurement in report.measurements where measurement.grade != .unavailable {
        #expect(measurement.grade != .failed, "\(measurement.title): \(measurement.detail)")
        #expect(measurement.samples >= 55)
        #expect(measurement.p95MS?.isFinite == true)
    }
}

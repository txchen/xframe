import Foundation
import Testing
@testable import XFrame

@Test func mlxPreparesAndExchangesOneFrameAtATime() throws {
    var now = 0.0
    var events: [String] = []
    let samples = try MLXBenchmarkSamples.collect(frameCount: 61, prepare: { index in
        events.append("prepare\(index)")
        now += 0.002
        return Data([UInt8(index)])
    }, clock: { now }, exchange: { frame, seed in
        let index = Int(frame[0])
        #expect(seed == (index == 0))
        events.append("exchange\(index)")
        now += 0.003
    })
    #expect(events == (0..<61).flatMap { ["prepare\($0)", "exchange\($0)"] })
    #expect(samples.helper.count == 55)
    #expect(samples.endToEnd.count == 55)
    #expect(samples.helper.allSatisfy { abs($0 - 3) < 0.000001 })
    #expect(samples.endToEnd.allSatisfy { abs($0 - 5) < 0.000001 })
}

@Test func mlxPreparationFailureStopsBeforeExchange() {
    enum Failure: Error { case preparation }
    var exchanges = 0
    #expect(throws: Failure.self) {
        try MLXBenchmarkSamples.collect(frameCount: 61, prepare: { index in
            if index == 2 { throw Failure.preparation }
            return Data([0])
        }, exchange: { _, _ in exchanges += 1 })
    }
    #expect(exchanges == 2)
}

@Test func mlxCapacityUsesPreparationInclusiveMeasurement() {
    let helper = BenchmarkMeasurement.measured("mlx1440", "Helper", detail: "", timing: "",
        values: [1], budgetMS: 10)
    let full = BenchmarkMeasurement.measured("mlxEndToEnd1440", "Full path", detail: "", timing: "",
        values: [12], budgetMS: 10)
    func report(_ rows: [BenchmarkMeasurement]) -> PostProcessingBenchmarkReport {
        .init(date: .now, device: "Test", macOS: "Test", fixture: "Test", measurements: rows, notes: [])
    }
    #expect(!report([helper, full]).capacitySummary.contains("has research-path headroom"))
    #expect(!report([helper]).capacitySummary.contains("has research-path headroom"))
    let fast = BenchmarkMeasurement.measured("mlxEndToEnd720", "Full path", detail: "", timing: "",
        values: [5], budgetMS: 10)
    #expect(report([helper, fast]).capacitySummary.contains("has research-path headroom"))
}

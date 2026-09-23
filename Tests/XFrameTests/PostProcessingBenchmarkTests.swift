import Foundation
import CryptoKit
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

@Test func benchmarkModelCacheImportsVerifiesAndRemoves() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("xframe-model-cache-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.safetensors")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let data = Data("test frame generation model".utf8)
    try data.write(to: source)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let cache = BenchmarkModelCache(directory: root.appendingPathComponent("cache"), expectedSHA256: digest)
    #expect(try cache.cachedModel() == nil)
    let cached = try cache.importModel(from: source)
    #expect(try cache.cachedModel() == cached)
    #expect(try Data(contentsOf: cached) == data)
    try Data("wrong model".utf8).write(to: source)
    #expect(throws: BenchmarkModelCacheError.self) { try cache.importModel(from: source) }
    #expect(try cache.cachedModel() == cached)
    try cache.remove()
    #expect(try cache.cachedModel() == nil)
}

@Test func benchmarkModelDownloaderRejectsNonHTTPS() async {
    let cache = BenchmarkModelCache()
    await #expect(throws: BenchmarkModelCacheError.self) {
        try await cache.download(from: URL(string: "http://example.com/framegen.safetensors")!)
    }
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

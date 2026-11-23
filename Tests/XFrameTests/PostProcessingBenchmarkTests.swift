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
    #expect(report.capacitySummary.contains("VideoToolbox not tested"))
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
    let report = try await PostProcessingBenchmark.run(selection: BenchmarkSelection(workloads: [.spatial1440, .vt720]), progress: { _ in })
    #expect(report.measurements.map(\.id) == ["spatial1440", "vt720"])
    for measurement in report.measurements where measurement.grade != .unavailable {
        #expect(measurement.grade != .failed, "\(measurement.title): \(measurement.detail)")
        #expect(measurement.samples == 15)
        #expect(measurement.p95MS?.isFinite == true)
    }
}

@Test func quickMLXRunStillExcludesWarmupAndMeasuresSelectedCount() throws {
    let result = try MLXBenchmarkSamples.collect(frameCount: BenchmarkLength.quick.samples + 6,
        prepare: { _ in Data([0]) }, exchange: { _, _ in })
    #expect(result.helper.count == 15)
    #expect(result.endToEnd.count == 15)
}

@Test func releaseModelsDownloadAndValidateWhenRequested() async throws {
    guard ProcessInfo.processInfo.environment["XFRAME_VERIFY_MODEL_DOWNLOADS"] == "1" else { return }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("xframe-download-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let fg = BenchmarkModelCache(directory: root.appendingPathComponent("fg"))
    let model = try await fg.download(from: BenchmarkReleaseModels.fgURL)
    #expect(try fg.cachedModel() == model)
    let nr = SmallNRModelCache(directory: root.appendingPathComponent("nr"))
    let package = try await BenchmarkReleaseModels.downloadNR(cache: nr)
    #expect(try SmallNRModelCache.validate(package) == BenchmarkReleaseModels.nrWeightsSHA256)
}

@Test func coreMLFGSelectionAndWeightLayoutAreValid() throws {
    let selection = BenchmarkSelection(workloads: [.coreml1080Balanced, .coreml1440Balanced])
    #expect(selection.needsFG)
    #expect(selection.needsCoreMLFG)
    #expect(!selection.needsMLXFG)
    #expect(CoreMLFGProfile.p720.shapeLabel == "368x640")
    #expect(CoreMLFGProfile.p1080Balanced.shapeLabel == "368x640")
    #expect(CoreMLFGProfile.p1080Quality.shapeLabel == "544x960")
    #expect(CoreMLFGProfile.p1440Balanced.shapeLabel == "480x864")
    #expect(CoreMLFGProfile.p1440Quality.shapeLabel == "720x1280")

    let templateDir = try CoreMLFrameGenerationBenchmark.templateDirectory(in: Bundle.module)
    let layoutData = try Data(contentsOf: templateDir.appendingPathComponent("weight-layout.json"))
    let layout = try JSONDecoder().decode(CoreMLFGWeightLayout.self, from: layoutData)
    #expect(layout.block0.chunks.count == 31)
    #expect(layout.block1.chunks.count == 29)
    for profile in CoreMLFGProfile.allCases {
        for stage in 0...1 {
            let dir = templateDir.appendingPathComponent("block\(stage)-\(profile.shapeLabel)")
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Manifest.json").path))
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("model.mlmodel").path))
        }
    }
}

@Test func coreMLFGRunsEndToEndWhenCachedWeightsExist() async throws {
    let cache = BenchmarkModelCache()
    guard let weightsURL = try cache.cachedModel() else { return }
    let safetensors = try SafetensorsFile(data: Data(contentsOf: weightsURL))
    let templateDir = try CoreMLFrameGenerationBenchmark.templateDirectory(in: Bundle.module)
    let layout = try JSONDecoder().decode(
        CoreMLFGWeightLayout.self,
        from: Data(contentsOf: templateDir.appendingPathComponent("weight-layout.json"))
    )
    let w0 = try layout.buildWeightBin(stageIndex: 0, from: safetensors)
    let w1 = try layout.buildWeightBin(stageIndex: 1, from: safetensors)
    let h0 = SHA256.hash(data: w0).map { String(format: "%02x", $0) }.joined()
    let h1 = SHA256.hash(data: w1).map { String(format: "%02x", $0) }.joined()
    #expect(h0 == "5c851cf252504ae0b867820c9d697789e9df65305d8e0746edf6f4c89d8c95f6")
    #expect(h1 == "762437693f7809273e367668359a2a12353d30a085ddb7a4855258a2c602980f")

    let report = try await PostProcessingBenchmark.run(
        selection: BenchmarkSelection(workloads: [.coreml1080Balanced], length: .quick),
        weightsURL: weightsURL,
        progress: { _ in }
    )
    #expect(report.measurements.count == 1)
    let row = try #require(report.measurements.first)
    #expect(row.id == "coreml1080Balanced")
    #expect(row.grade != .failed && row.grade != .unavailable, "\(row.detail)")
    #expect(row.samples == 15)
    #expect(row.medianMS != nil && row.p95MS != nil)
}

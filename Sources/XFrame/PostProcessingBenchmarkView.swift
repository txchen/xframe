import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PostProcessingBenchmarkModel: ObservableObject {
    @Published var report: PostProcessingBenchmarkReport?
    @Published var status = "Ready. The test uses a bundled video and leaves playback settings unchanged."
    @Published var running = false
    @Published var weightsURL: URL?
    private var worker: Task<PostProcessingBenchmarkReport, Error>?
    private let sessionActive: () -> Bool

    init(sessionActive: @escaping () -> Bool) { self.sessionActive = sessionActive }

    func start() {
        guard !running else { return }
        guard !sessionActive() else {
            status = "End the active streaming session before benchmarking so its GPU work does not distort the result."
            return
        }
        running = true
        report = nil
        status = "Starting…"
        let model = self
        let selectedWeights = weightsURL
        let worker = Task.detached(priority: .userInitiated) {
            let access = selectedWeights?.startAccessingSecurityScopedResource() ?? false
            defer { if access { selectedWeights?.stopAccessingSecurityScopedResource() } }
            return try await PostProcessingBenchmark.run(weightsURL: selectedWeights) { message in
                Task { @MainActor in model.status = message }
            }
        }
        self.worker = worker
        Task { [weak self] in
            do {
                let result = try await worker.value
                self?.report = result
                self?.status = "Complete. Export JSON to compare this machine with another one."
            } catch is CancellationError {
                self?.status = "Benchmark cancelled."
            } catch {
                self?.status = "Benchmark failed: \(error.localizedDescription)"
            }
            self?.running = false
            self?.worker = nil
        }
    }

    func cancel() { worker?.cancel() }

    func chooseWeights() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "safetensors") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            if response == .OK { self?.weightsURL = panel.url }
        }
    }

    func export() {
        guard let report else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "xframe-post-processing-benchmark.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(report).write(to: url, options: .atomic)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
}

struct PostProcessingBenchmarkView: View {
    @ObservedObject var model: PostProcessingBenchmarkModel

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Post-Processing Benchmark").font(.title2.weight(.semibold))
                    Text("60 Hz target · bundled 1080p30 video · local processing only")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.running {
                    Button("Cancel") { model.cancel() }
                } else {
                    Button("Run Benchmark") { model.start() }.buttonStyle(.borderedProminent)
                }
            }
            Text(model.status).font(.subheadline)
                .foregroundStyle(model.status.hasPrefix("Benchmark failed") ? .red : .secondary)
            HStack(spacing: 8) {
                Button("Choose MLX-DLSS Weights…") { model.chooseWeights() }
                    .disabled(model.running)
                if let weights = model.weightsURL {
                    Text(weights.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Button("Clear") { model.weightsURL = nil }.disabled(model.running)
                } else {
                    Text("Optional · no weights selected").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            if model.running { ProgressView().progressViewStyle(.linear) }
            Divider()
            if let report = model.report {
                HStack {
                    Text("\(report.device) · \(report.macOS)")
                        .font(.headline)
                    Spacer()
                    Button("Export JSON…") { model.export() }
                }
                Text(report.capacitySummary).font(.subheadline.weight(.medium))
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(report.measurements) { measurement in
                            measurementRow(measurement)
                        }
                    }
                }
                Text("Headroom: p95 ≤ 70% of frame budget. Tight: ≤ 100%. Frame-generation grades assume native input at the tested size. Game FPS, image quality and added latency are unmeasured.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Optional MLX-DLSS measures a separate video research path. Its model stays on your Mac; this test does not enable live game frame generation.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Tests MetalFX at 1440p and 4K, 4K with High sharpening, and VideoToolbox 720p / 1080p / 1440p 30 → 60 fps. Select local weights to add MLX-DLSS video generation at those three input sizes. Each workload runs offscreen, away from a game session.")
                    .font(.body).foregroundStyle(.secondary)
                Spacer()
            }
            Text("Video excerpt: Big Buck Bunny © Blender Foundation, CC BY 3.0 · modified to silent 1080p30")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(22)
        .frame(minWidth: 660, minHeight: 475)
    }

    private func measurementRow(_ item: BenchmarkMeasurement) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline)
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                Text("\(item.timing) · \(item.samples) samples · budget \(item.budgetMS, specifier: "%.2f") ms")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 14)
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.grade.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(color(for: item.grade))
                if let median = item.medianMS, let p95 = item.p95MS {
                    Text("median \(median, specifier: "%.1f") · p95 \(p95, specifier: "%.1f") ms")
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func color(for grade: BenchmarkGrade) -> Color {
        switch grade {
        case .headroom: .green
        case .tight: .orange
        case .overBudget, .failed: .red
        case .unavailable: .secondary
        }
    }
}

@MainActor
final class BenchmarkWindowLifecycle: NSObject, NSWindowDelegate {
    private let model: PostProcessingBenchmarkModel
    init(model: PostProcessingBenchmarkModel) { self.model = model }
    func windowWillClose(_ notification: Notification) { model.cancel() }
}

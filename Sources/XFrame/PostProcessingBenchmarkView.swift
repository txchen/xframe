import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PostProcessingBenchmarkModel: ObservableObject {
    @Published var selection = BenchmarkSelection()
    @Published var report: PostProcessingBenchmarkReport?
    @Published var status = "Ready. Test video and optional Core ML weights download on demand."
    @Published var running = false
    @Published var weightsURL: URL?
    @Published var modelBusy = false
    @Published var smallNRURL: URL?
    private let smallNRCache = SmallNRModelCache()
    private var worker: Task<PostProcessingBenchmarkReport, Error>?
    private let sessionActive: () -> Bool
    private let modelCache = BenchmarkModelCache()

    init(sessionActive: @escaping () -> Bool) {
        self.sessionActive = sessionActive
        do { smallNRURL = try smallNRCache.cachedModel() }
        catch { status = "Small NR cache needs replacement: \(error.localizedDescription)" }
        if let bundled = BenchmarkModelCache.bundledModel() {
            weightsURL = bundled
            status = "Ready. Core ML FG weights are bundled; benchmark video downloads on demand."
        } else {
            do {
                weightsURL = try modelCache.cachedModel()
                if weightsURL != nil { status = "Ready. Choose the tests to run; cached weights are available." }
            } catch {
                status = "Cached MLX-DLSS model needs replacement: \(error.localizedDescription)"
            }
        }
    }

    func start() {
        guard !running, !modelBusy else { return }
        guard !sessionActive() else {
            status = "End the active streaming session before benchmarking so its GPU work does not distort the result."
            return
        }
        guard !selection.workloads.isEmpty else { status = "Select at least one test."; return }
        running = true
        report = nil
        status = "Starting…"
        let model = self
        let options = selection
        let cachedFG = weightsURL
        let cachedNR = smallNRURL
        let fgCache = modelCache
        let nrCache = smallNRCache
        let worker = Task.detached(priority: .userInitiated) {
            var selectedWeights = options.needsFG ? cachedFG : nil
            var selectedNR = options.needsNR ? cachedNR : nil
            if options.needsFG && selectedWeights == nil {
                await MainActor.run { model.status = "Downloading Core ML FG weights from GitHub Release (2.9 MB)…" }
                selectedWeights = try await fgCache.download(from: BenchmarkReleaseModels.fgURL)
                let downloaded = selectedWeights
                await MainActor.run { model.weightsURL = downloaded }
            }
            try Task.checkCancellation()
            if options.needsNR && selectedNR == nil {
                await MainActor.run { model.status = "Downloading Small NR from GitHub Release (about 97 MB), then verifying…" }
                selectedNR = try await BenchmarkReleaseModels.downloadNR(cache: nrCache)
                let downloaded = selectedNR
                await MainActor.run { model.smallNRURL = downloaded }
            }
            try Task.checkCancellation()
            return try await PostProcessingBenchmark.run(selection: options, weightsURL: selectedWeights, smallNRURL: selectedNR) { message in
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
                self?.status = worker.isCancelled ? "Benchmark cancelled." : "Benchmark failed: \(error.localizedDescription)"
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
            guard response == .OK, let source = panel.url, let self else { return }
            self.modelBusy = true
            self.status = "Importing and verifying model…"
            let cache = self.modelCache
            Task { [weak self] in
                do {
                    let url = try await Task.detached {
                        let access = source.startAccessingSecurityScopedResource()
                        defer { if access { source.stopAccessingSecurityScopedResource() } }
                        return try cache.importModel(from: source)
                    }.value
                    self?.weightsURL = url
                    self?.status = "Model cached. Select MLX frame-generation tests to include them."
                } catch {
                    self?.status = "Model import failed: \(error.localizedDescription)"
                }
                self?.modelBusy = false
            }
        }
    }

    func chooseSmallNR() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.treatsFilePackagesAsDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the extracted NeuralRendering-Small.dlssmodel folder from DLSS NR 310.9.16.0."
        panel.begin { [weak self] response in
            guard response == .OK, let source = panel.url, let self else { return }
            self.modelBusy = true
            self.status = "Verifying and caching Small NR…"
            let cache = self.smallNRCache
            Task { [weak self] in
                do {
                    let url = try await Task.detached {
                        let access = source.startAccessingSecurityScopedResource()
                        defer { if access { source.stopAccessingSecurityScopedResource() } }
                        return try cache.importModel(from: source)
                    }.value
                    self?.smallNRURL = url
                    self?.status = "Small NR cached. Select the Small NR resolutions you want to test."
                } catch { self?.status = "Small NR import failed: \(error.localizedDescription)" }
                self?.modelBusy = false
            }
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
                    Text("60 Hz target · on-demand 1080p30 video · native Metal, VideoToolbox & Core ML ANE")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.running {
                    Button("Cancel") { model.cancel() }
                } else {
                    Button("Run Benchmark") { model.start() }
                        .buttonStyle(.borderedProminent).disabled(model.modelBusy || model.selection.workloads.isEmpty)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Choose tests").font(.title3.bold())
                        Spacer()
                        Button("Recommended") { model.selection.workloads = BenchmarkSelection().workloads }
                        Button("All") {
                            let visibleGroups = Set(["MetalFX scaling", "VideoToolbox interpolation", "Core ML frame generation · ANE + Metal"])
                            model.selection.workloads = Set(BenchmarkWorkload.allCases.filter { visibleGroups.contains($0.group) })
                        }
                        Button("None") { model.selection.workloads = [] }
                    }
                    ForEach(["MetalFX scaling", "VideoToolbox interpolation", "Core ML frame generation · ANE + Metal"], id: \.self) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group).font(.system(size: 17, weight: .semibold))
                            let items = BenchmarkWorkload.allCases.filter { $0.group == group }
                            if group == "Core ML frame generation · ANE + Metal" {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .leading)], alignment: .leading, spacing: 10) {
                                    ForEach(items) { item in
                                        Toggle(item.title, isOn: Binding(get: { model.selection.workloads.contains(item) }, set: { selected in
                                            if selected { model.selection.workloads.insert(item) }
                                            else { model.selection.workloads.remove(item) }
                                        }))
                                    }
                                }
                            } else {
                                HStack(spacing: 22) {
                                    ForEach(items) { item in
                                        Toggle(item.title, isOn: Binding(get: { model.selection.workloads.contains(item) }, set: { selected in
                                            if selected { model.selection.workloads.insert(item) }
                                            else { model.selection.workloads.remove(item) }
                                        }))
                                    }
                                }
                            }
                            if group == "Core ML frame generation · ANE + Metal" {
                                HStack {
                                    Text(model.weightsURL == nil ? "2.8 MB FG weights · compiles Core ML once on first run" : "Bundled 2.8 MB FG weights ready · compiles Core ML once on first run")
                                    Spacer()
                                    Button("Import…") { model.chooseWeights() }
                                }.font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                            if group == "MLX frame generation" {
                                HStack {
                                    Text(model.weightsURL == nil ? "2.9 MB · downloads automatically when selected" : "Weights ready on this Mac")
                                    Spacer()
                                    Button("Import…") { model.chooseWeights() }
                                }.font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                            if group == "Small NR · research" {
                                HStack {
                                    Text(model.smallNRURL == nil ? "97 MB download · slow on lightweight Macs" : "Weights ready · slow on lightweight Macs")
                                    Spacer()
                                    Button("Import…") { model.chooseSmallNR() }
                                }.font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(LibraryStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                    }

                }.disabled(model.running || model.modelBusy)
            }.frame(minHeight: 270, maxHeight: 420)
                    Picker("Test length", selection: $model.selection.length) {
                        ForEach(BenchmarkLength.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).disabled(model.running || model.modelBusy)
                    Text("\(model.selection.workloads.count) tests selected. Quick is for screening; use Standard for more reliable P95 results. Warmups are excluded. Missing selected weights download from XFrame’s GitHub Release and are verified before use.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
            Text(model.status).font(.system(size: 15)).textSelection(.enabled)
            if model.running || model.modelBusy { ProgressView().progressViewStyle(.linear) }
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
                Text("Only selected tests run. These offline measurements do not enable live frame generation or measure controller latency.")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                Spacer()
            }
            Text("Video excerpt: Big Buck Bunny © Blender Foundation, CC BY 3.0 · modified to silent 1080p30")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(22)
        .frame(minWidth: 780, minHeight: 720)
        .background(LibraryStyle.canvas).foregroundStyle(.white).tint(LibraryStyle.accent).preferredColorScheme(.dark)
    }

    private func measurementRow(_ item: BenchmarkMeasurement) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline)
                DisclosureGroup("Details · \(item.samples) samples") {
                    Text(item.detail).font(.system(size: 14)).foregroundStyle(.secondary)
                    Text("\(item.timing) · budget \(item.budgetMS, specifier: "%.2f") ms")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }.font(.system(size: 14))
            }
            Spacer(minLength: 14)
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.grade.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(color(for: item.grade))
                if let median = item.medianMS, let p95 = item.p95MS {
                    Text("median \(median, specifier: "%.1f") · p95 \(p95, specifier: "%.1f") ms")
                        .font(.system(size: 16, design: .monospaced))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LibraryStyle.surface, in: RoundedRectangle(cornerRadius: 10))
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

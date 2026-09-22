import SwiftUI

struct CloudLibraryView: View {
    let library: CloudLibrary
    let account: XboxAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack {
                TextField("Search games", text: Binding(get: { library.search }, set: { library.search = $0 }))
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Search games")
                if !library.search.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") { library.search = "" }.labelStyle(.iconOnly)
                }
                Button(library.catalogLoaded ? "Refresh Games" : "Load Games", systemImage: "arrow.clockwise") {
                    do { library.load(using: try account.cloudService()); library.viewError = nil }
                    catch { library.viewError = error.localizedDescription }
                }.disabled(account.isBusy || library.loading || library.ownsSession)
            }
            GameBrowserView(library: library)
            Divider()
            sessionControls
        }.padding(24).frame(minWidth: 900, minHeight: 720).tint(.green)
            .fileExporter(isPresented: Binding(get: { library.exportingDiagnostics }, set: { library.exportingDiagnostics = $0 }),
                          document: library.diagnosticDocument, contentType: .json, defaultFilename: "xframe-stream-diagnostics") { result in
                if case .failure = result { library.viewError = "Could not save stream diagnostics." }
            }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cloud Games").font(.largeTitle.bold())
                Text("Your next game, on your Mac.").foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Picker("Region", selection: Binding(get: { account.selectedRegion }, set: { account.selectRegion($0) })) {
                    Text("Automatic (service default)").tag("")
                    ForEach(account.regionNames, id: \.self) { Text($0).tag($0) }
                }.frame(width: 290)
                    .disabled(account.isBusy || library.loading || library.ownsSession || account.regionNames.isEmpty)
                Text("Requested: \(account.requestedRegion ?? "Not available") · Service may redirect")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var sessionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(library.activeGame ?? library.selectedGame?.name ?? "Select a game to begin").font(.headline).lineLimit(1)
                    Text(library.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if library.ending { ProgressView().controlSize(.small) }
                if library.ownsSession {
                    Button("End Session") { library.end() }.disabled(library.ending)
                } else {
                    Button("Start Selected Game", systemImage: "play.fill") {
                        if let game = library.selectedGame { library.start(game) }
                    }.buttonStyle(.borderedProminent)
                        .disabled(library.selectedGame == nil || library.loading || account.isBusy)
                }
            }
            HStack {
                Toggle("Mute game audio", isOn: Binding(get: { library.audioMuted }, set: {
                    library.setAudio(muted: $0, volume: library.audioVolume)
                }))
                Slider(value: Binding(get: { library.audioVolume }, set: {
                    library.setAudio(muted: library.audioMuted, volume: $0)
                }), in: 0...1) { Text("Game volume") }.frame(width: 130)
                Text("\(Int(library.audioVolume * 100))%").monospacedDigit().frame(width: 42)
                Spacer()
                Text("Microphone and controller input disabled").font(.caption).foregroundStyle(.secondary)
            }
            if let error = library.viewError ?? library.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let diagnostics = library.lastVideoDiagnostics, !diagnostics.isEmpty {
                DisclosureGroup("Last stream diagnostics") {
                    ScrollView {
                        Text(diagnostics).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 100)
                    if let report = library.lastStreamReport {
                        Button("Export JSON…") {
                            do {
                                library.diagnosticDocument = try StreamDiagnosticDocument(report: report)
                                library.exportingDiagnostics = true
                            } catch { library.viewError = "Could not prepare stream diagnostics." }
                        }
                    }
                }
            }
        }
    }
}

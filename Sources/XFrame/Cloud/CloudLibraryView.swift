import SwiftUI

struct CloudLibraryView: View {
    let library: CloudLibrary
    let account: XboxAccount
    private var filtered: [CloudGame] {
        library.games.filter { library.search.isEmpty || $0.name.localizedCaseInsensitiveContains(library.search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cloud Games").font(.title.bold())
            Text("H.264 video and game audio preview. Microphone and controller input are disabled.")
                .foregroundStyle(.secondary)
            HStack {
                Toggle("Mute game audio", isOn: Binding(get: { library.audioMuted }, set: {
                    library.setAudio(muted: $0, volume: library.audioVolume)
                }))
                Slider(value: Binding(get: { library.audioVolume }, set: {
                    library.setAudio(muted: library.audioMuted, volume: $0)
                }), in: 0...1) { Text("Game volume") }.frame(maxWidth: 160)
                Text("\(Int(library.audioVolume * 100))%")
            }
            Picker("Region", selection: Binding(get: { account.selectedRegion }, set: { account.selectRegion($0) })) {
                Text("Automatic (service default)").tag("")
                ForEach(account.regionNames, id: \.self) { Text($0).tag($0) }
            }.disabled(account.isBusy || library.loading || library.ownsSession || account.regionNames.isEmpty)
            Text("Requested region: \(account.requestedRegion ?? "Not available"). The service may redirect the session.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Changing region clears the catalog. Load Games again before starting a session.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Search games", text: Binding(get: { library.search }, set: { library.search = $0 }))
                Button("Load Games") {
                    do { library.load(using: try account.cloudService()); library.viewError = nil }
                    catch { library.viewError = error.localizedDescription }
                }.disabled(account.isBusy || library.loading || library.ownsSession)
            }
            List(filtered, selection: Binding(get: { library.selection }, set: { library.selection = $0 })) { game in Text(game.name).tag(game.id) }
            Text(library.status).font(.headline)
            if let diagnostics = library.lastVideoDiagnostics, !diagnostics.isEmpty {
                DisclosureGroup("Last stream diagnostics (latest 128 events)") {
                    ScrollView {
                        Text(diagnostics).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 140)
                }
            }
            if let error = library.viewError ?? library.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if library.loading || library.ending { ProgressView().controlSize(.small) }
                Button("Start Session") {
                    if let game = library.games.first(where: { $0.id == library.selection }) { library.start(game) }
                }.disabled(library.selection == nil || library.ownsSession || library.loading || account.isBusy)
                if library.ownsSession {
                    Button("End Session") { library.end() }.disabled(library.ending)
                }
            }
        }.padding(20).frame(minWidth: 640, minHeight: 520)
    }
}

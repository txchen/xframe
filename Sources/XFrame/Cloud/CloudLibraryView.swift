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
            Text("Session test only. No video, audio, or controller input. Ready sessions end automatically after 60 seconds.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Search games", text: Binding(get: { library.search }, set: { library.search = $0 }))
                Button("Load Games") {
                    do { library.load(using: try account.cloudService()); library.viewError = nil }
                    catch { library.viewError = error.localizedDescription }
                }.disabled(account.isBusy || library.loading || library.ownsSession)
            }
            List(filtered, selection: Binding(get: { library.selection }, set: { library.selection = $0 })) { game in Text(game.name).tag(game.id) }
            Text(library.status).font(.headline)
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

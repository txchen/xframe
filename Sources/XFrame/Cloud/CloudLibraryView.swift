import SwiftUI

struct CloudLibraryView: View {
    let library: CloudLibrary
    let account: XboxAccount

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            if account.hasCloudAccess {
            VStack(alignment: .leading, spacing: 20) {
            header
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(LibraryStyle.secondary)
                TextField("Search games", text: Binding(get: { library.search }, set: { library.search = $0 }))
                    .textFieldStyle(.plain).font(.system(size: 14)).accessibilityLabel("Search games")
                if !library.search.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") { library.search = "" }.labelStyle(.iconOnly)
                }
                Button(library.catalogLoaded ? "Refresh Games" : "Load Games", systemImage: "arrow.clockwise") {
                    do { library.load(using: try account.cloudService()); library.viewError = nil }
                    catch { library.viewError = error.localizedDescription }
                }.buttonStyle(.borderless).tint(.white)
                    .disabled(account.isBusy || library.loading || library.ownsSession)
            }.padding(.horizontal, 16).padding(.vertical, 13)
                .background(LibraryStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            GameBrowserView(library: library)
            Divider()
            sessionControls
            }.padding(24)
            } else {
                XboxAccountView(account: account)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(minWidth: 900, minHeight: 720)
            .background(LibraryStyle.canvas).foregroundStyle(.white).tint(LibraryStyle.accent)
            .preferredColorScheme(.dark)
            .sheet(isPresented: Binding(get: { account.showingAccount }, set: { account.showingAccount = $0 })) {
                VStack(alignment: .trailing, spacing: 0) {
                    Button("Done") { account.showingAccount = false }
                        .keyboardShortcut(.cancelAction).padding([.top, .trailing], 20)
                    XboxAccountView(account: account)
                }.background(LibraryStyle.canvas).preferredColorScheme(.dark)
            }
            .sheet(isPresented: Binding(get: { library.showingStreamSettings }, set: { library.showingStreamSettings = $0 })) {
                CloudStreamSettingsView(library: library)
            }
            .onChange(of: account.hasCloudAccess) { _, _ in account.showingAccount = false }
            .fileExporter(isPresented: Binding(get: { library.exportingDiagnostics }, set: { library.exportingDiagnostics = $0 }),
                          document: library.diagnosticDocument, contentType: .json, defaultFilename: "xframe-stream-diagnostics") { result in
                if case .failure = result { library.viewError = "Could not save stream diagnostics." }
            }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 21))
                    .foregroundStyle(LibraryStyle.accent)
                Text("XFRAME").font(.system(size: 15, weight: .heavy, design: .rounded)).tracking(1.5)
            }.padding(.top, 10)
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR LIBRARY").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(LibraryStyle.secondary).padding(.bottom, 6)
                collectionButton("Games", icon: "square.grid.2x2", favorites: false)
                collectionButton("Favorites", icon: "star", favorites: true)
            }.disabled(!account.hasCloudAccess)
            Spacer()
            Button {
                library.showingStreamSettings = true
            } label: {
                Label("Streaming Settings", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
            }.buttonStyle(.plain).accessibilityLabel("Streaming Settings")
            Button {
                account.showingAccount = account.hasCloudAccess
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 24))
                        .foregroundStyle(LibraryStyle.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.gamertag ?? "Xbox account").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(account.isBusy ? "Connecting…" : account.hasCloudAccess ? "Manage account" : "Sign in")
                            .font(.system(size: 10)).foregroundStyle(LibraryStyle.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).accessibilityLabel("Xbox Account")
            VStack(alignment: .leading, spacing: 10) {
                Label("Xbox Cloud Gaming", systemImage: "cloud").font(.system(size: 12, weight: .medium))
                Text("Native video.\nYour games, closer.").font(.system(size: 12)).lineSpacing(4)
                    .foregroundStyle(LibraryStyle.secondary)
                Text("DEVELOPMENT PREVIEW").font(.system(size: 8, weight: .semibold)).tracking(1)
                    .foregroundStyle(LibraryStyle.secondary).padding(.top, 12)
            }
        }.padding(18).frame(width: 164).frame(maxHeight: .infinity)
            .background(LibraryStyle.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(LibraryStyle.border).frame(width: 1) }
    }

    private func collectionButton(_ title: String, icon: String, favorites: Bool) -> some View {
        let selected = library.query.favoritesOnly == favorites
        return Button {
            library.updateQuery { $0.favoritesOnly = favorites }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? icon + ".fill" : icon).frame(width: 16)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .foregroundStyle(selected ? LibraryStyle.accent : LibraryStyle.secondary)
                .background(selected ? LibraryStyle.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(library.query.favoritesOnly ? "Favorites" : "Cloud library")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(library.catalogLoaded ? "\(library.games.count.formatted()) games. Find your next adventure." : "Great games. A little closer.")
                    .font(.system(size: 13)).foregroundStyle(LibraryStyle.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Picker("Region", selection: Binding(get: { account.selectedRegion }, set: { account.selectRegion($0) })) {
                    Text("Automatic").tag("")
                    ForEach(account.regionNames, id: \.self) { Text($0).tag($0) }
                }.frame(width: 230).tint(.white)
                    .disabled(account.isBusy || library.loading || library.ownsSession || account.regionNames.isEmpty)
                Text("\(account.requestedRegion ?? "No region") · Requested region")
                    .font(.system(size: 10)).foregroundStyle(LibraryStyle.secondary)
                    .help("The service may redirect the session. Changing region clears the catalog.")
            }
        }
    }

    private var sessionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(library.activeGame ?? library.selectedGame?.name ?? "Select a game to begin").font(.headline).lineLimit(1)
                    Text(library.selectedGame.map { $0.access.label + " · " + library.status } ?? library.status).font(.caption).foregroundStyle(LibraryStyle.secondary)
                }
                Spacer()
                if library.ending { ProgressView().controlSize(.small) }
                if library.ownsSession {
                    Button("End Session") { library.requestEndSession?() }.disabled(library.ending)
                } else {
                    if let game = library.retryGame {
                        Button("Retry \(game.name)") { library.retry() }.disabled(account.isBusy)
                    }
                    Button {
                        if let game = library.selectedGame { library.start(game) }
                    } label: {
                        Label("Play game", systemImage: "play.fill").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(LibraryStyle.canvas).padding(.horizontal, 22).padding(.vertical, 12)
                            .background(LibraryStyle.accent, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityLabel("Start Selected Game")
                        .opacity(library.selectedGame?.access.playable != true || library.loading || account.isBusy ? 0.35 : 1)
                        .disabled(library.selectedGame?.access.playable != true || library.loading || account.isBusy)
                }
            }
            Text(library.activeStreamPreferences.map { "Session: \($0.summary)" }
                 ?? "Next session: \(library.streamPreferences.summary)")
                .font(.caption).foregroundStyle(LibraryStyle.secondary)
            HStack {
                Toggle("Mute game audio", isOn: Binding(get: { library.audioMuted }, set: {
                    library.setAudio(muted: $0, volume: library.audioVolume)
                }))
                Slider(value: Binding(get: { library.audioVolume }, set: {
                    library.setAudio(muted: library.audioMuted, volume: $0)
                }), in: 0...1) { Text("Game volume") }.frame(width: 130)
                Text("\(Int(library.audioVolume * 100))%").monospacedDigit().frame(width: 42)
                Spacer()
                Text(library.keyboardEnabled && library.controllerEnabled ? "Keyboard + Controller · automatic switching" : library.keyboardEnabled ? "Keyboard enabled · View > Keyboard Controls" : library.controllerEnabled ? "Controller enabled · Microphone off" : "Input: enable in View menu · Microphone off").font(.system(size: 10)).foregroundStyle(LibraryStyle.secondary)
            }
            if let error = library.viewError ?? library.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Button("Export frame timing sample…") { library.exportFrameTimingSample() }
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

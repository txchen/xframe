import SwiftUI

struct GameBrowserView: View {
    let library: CloudLibrary
    @AppStorage("XFrame.LargeLibrary") private var large = false

    var body: some View {
        VStack(spacing: 18) {
            filters
            catalog
                .onMoveCommand { direction in
                    switch direction {
                    case .left, .up: library.moveSelection(by: -1)
                    case .right, .down: library.moveSelection(by: 1)
                    @unknown default: break
                    }
                }
            pagination
        }
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { filterOptions; Spacer(); displayOptions }
            VStack(alignment: .leading, spacing: 12) { filterOptions; displayOptions }
        }.font(.system(size: large ? 17 : 15)).controlSize(.large)
    }

    private var filterOptions: some View {
        HStack(spacing: 12) {
            Picker("Access", selection: Binding(get: { library.query.access }, set: { value in library.updateQuery { $0.access = value } })) {
                ForEach(GameLibraryQuery.Access.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(width: 180)
            Picker("Category", selection: Binding(get: { library.query.category }, set: { value in
                library.updateQuery { $0.category = value }
            })) {
                Text("All categories").tag("")
                ForEach(library.categories, id: \.self) { Text($0).tag($0) }
            }.frame(maxWidth: 230)
            Picker("Sort", selection: Binding(get: { library.query.sort }, set: { value in
                library.updateQuery { $0.sort = value }
            })) {
                ForEach(GameLibraryQuery.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.frame(width: 115)
        }
    }

    private var displayOptions: some View {
        HStack(spacing: 12) {
            Picker("Size", selection: $large) { Text("Standard").tag(false); Text("Large").tag(true) }
                .pickerStyle(.segmented).frame(width: 220)
            Picker("View", selection: Binding(get: { library.query.layout }, set: { library.query.layout = $0 })) {
                ForEach(GameLibraryQuery.Layout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 105)
        }.tint(.white)
    }

    @ViewBuilder private var catalog: some View {
        if library.loading && !library.catalogLoaded {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading your library").font(.title2.bold())
                Text("Fetching cloud titles and public catalog details.").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !library.catalogLoaded {
            emptyState("Find your next game", subtitle: "Sign in, choose a region, then load the cloud catalog.", icon: "gamecontroller")
        } else if library.page.total == 0 {
            VStack {
                let emptyTitle = library.query.recentlyPlayedOnly ? "No recently played games"
                    : library.query.favoritesOnly ? "No matching favorites" : "No games found"
                emptyState(emptyTitle,
                    subtitle: "Try another filter. All cloud games includes unavailable and unverified titles.", icon: "magnifyingglass")
                Button("Reset Filters") {
                    library.updateQuery { $0.search = ""; $0.category = ""; $0.favoritesOnly = false; $0.recentlyPlayedOnly = false; $0.access = .playable }
                }
                Button("Browse All Cloud Games") { library.updateQuery { $0.access = .all } }
                    .padding(.bottom, 20)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if library.query.layout == .grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: large ? 235 : 190, maximum: large ? 300 : 250), spacing: 20)], spacing: 22) {
                    ForEach(library.page.games) { game in
                        GameLibraryCard(game: game, large: large, selected: library.selection == game.id,
                            favorite: library.favorites.contains(game.id), select: { library.selection = game.id },
                            toggleFavorite: { library.toggleFavorite(game) },
                            artworkRevision: library.artworkRevisions[game.id, default: 0])
                            .contextMenu {
                                Button("Reload Artwork") { library.reloadArtwork(for: game) }
                                    .disabled(game.posterURL == nil)
                            }
                    }
                }.padding(4)
            }.id(library.query).scrollContentBackground(.hidden)
        } else {
            List(selection: Binding(get: { library.selection }, set: { library.selection = $0 })) {
                ForEach(library.page.games) { game in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.name).font(.system(size: large ? 21 : 18, weight: .semibold))
                            Text(game.access.label).font(.system(size: 14)).foregroundStyle(game.access.playable ? LibraryStyle.accent : .orange)
                            Text(game.categories.joined(separator: " · ")).font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(game.publisher ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Button { library.toggleFavorite(game) } label: {
                            Image(systemName: library.favorites.contains(game.id) ? "star.fill" : "star")
                        }.buttonStyle(.borderless).accessibilityLabel("Toggle favorite for \(game.name)")
                    }.padding(.vertical, 9).tag(game.id)
                        .listRowBackground(library.selection == game.id ? LibraryStyle.accent.opacity(0.12) : LibraryStyle.canvas)
                }
            }.id(library.query).scrollContentBackground(.hidden)
        }
    }

    private func emptyState(_ title: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 38)).foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }

    private var pagination: some View {
        let page = library.page
        return HStack {
            Text("\(page.first)–\(page.last) of \(page.total.formatted()) games").font(.system(size: 14)).foregroundStyle(LibraryStyle.secondary)
            Spacer()
            Picker("Per page", selection: Binding(get: { library.query.pageSize }, set: { value in
                library.updateQuery { $0.pageSize = value }
            })) { ForEach([24, 48, 96], id: \.self) { Text("\($0)").tag($0) } }.frame(width: 140)
            Button("Previous", systemImage: "chevron.left") { library.goToPage(page.index - 1) }
                .disabled(page.index == 0 || (library.loading && !library.catalogLoaded))
            Text("\(page.index + 1) / \(page.count)").monospacedDigit().frame(minWidth: 64)
            Button("Next", systemImage: "chevron.right") { library.goToPage(page.index + 1) }
                .disabled(page.index + 1 >= page.count || (library.loading && !library.catalogLoaded))
        }.font(.system(size: 14)).tint(.white).controlSize(.regular)
    }
}

private struct GameLibraryCard: View {
    let game: CloudGame
    let large: Bool
    let selected, favorite: Bool
    let select, toggleFavorite: () -> Void
    let artworkRevision: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geometry in
                        CachedPosterImage(url: game.posterURL, revision: artworkRevision)
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped().accessibilityHidden(true)
                    }.aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(game.name).font(.system(size: large ? 21 : 18, weight: .semibold)).lineLimit(2).frame(height: large ? 54 : 48, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 3)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Select \(game.name)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            if !game.access.playable {
                Text(game.access.label).font(.system(size: 14)).foregroundStyle(.orange)
                    .lineLimit(1).padding(.horizontal, 10).padding(.bottom, 10)
            }


        }
        .overlay(alignment: .topTrailing) {
            Button(action: toggleFavorite) { Image(systemName: favorite ? "star.fill" : "star").font(.system(size: 19))
                .padding(8).background(.black.opacity(0.65), in: Circle()) }
                .buttonStyle(.plain).padding(8).accessibilityLabel("Toggle favorite for \(game.name)")
        }
        .background(selected ? LibraryStyle.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? LibraryStyle.accent : .clear, lineWidth: 2) }
    }
}

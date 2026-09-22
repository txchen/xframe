import SwiftUI

struct GameBrowserView: View {
    let library: CloudLibrary

    var body: some View {
        VStack(spacing: 12) {
            filters
            catalog
            pagination
        }
    }

    private var filters: some View {
        HStack {
            Toggle("Favorites", isOn: Binding(get: { library.query.favoritesOnly }, set: { value in
                library.updateQuery { $0.favoritesOnly = value }
            })).toggleStyle(.button)
            Picker("Category", selection: Binding(get: { library.query.category }, set: { value in
                library.updateQuery { $0.category = value }
            })) {
                Text("All categories").tag("")
                ForEach(library.categories, id: \.self) { Text($0).tag($0) }
            }.frame(maxWidth: 270)
            Picker("Sort", selection: Binding(get: { library.query.sort }, set: { value in
                library.updateQuery { $0.sort = value }
            })) {
                ForEach(GameLibraryQuery.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.frame(width: 130)
            Spacer()
            Picker("View", selection: Binding(get: { library.query.layout }, set: { library.query.layout = $0 })) {
                ForEach(GameLibraryQuery.Layout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width: 140)
        }
    }

    @ViewBuilder private var catalog: some View {
        if library.loading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading your library").font(.title2.bold())
                Text("Fetching cloud titles and public catalog details.").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !library.catalogLoaded {
            emptyState("Find your next game", subtitle: "Sign in, choose a region, then load the cloud catalog.", icon: "gamecontroller")
        } else if library.page.total == 0 {
            VStack {
                emptyState(library.query.favoritesOnly ? "No matching favorites" : "No games found",
                    subtitle: "Try another search or category. Star a game to save a favorite.", icon: "magnifyingglass")
                Button("Reset Filters") { library.updateQuery { $0.search = ""; $0.category = ""; $0.favoritesOnly = false } }
                    .padding(.bottom, 20)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if library.query.layout == .grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)], spacing: 16) {
                    ForEach(library.page.games) { game in
                        GameLibraryCard(game: game, selected: library.selection == game.id,
                            favorite: library.favorites.contains(game.id), select: { library.selection = game.id },
                            toggleFavorite: { library.toggleFavorite(game) })
                    }
                }.padding(4)
            }.id(library.query)
        } else {
            List(selection: Binding(get: { library.selection }, set: { library.selection = $0 })) {
                ForEach(library.page.games) { game in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.name).font(.headline)
                            Text(game.categories.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(game.publisher ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Button { library.toggleFavorite(game) } label: {
                            Image(systemName: library.favorites.contains(game.id) ? "star.fill" : "star")
                        }.buttonStyle(.borderless).accessibilityLabel("Toggle favorite for \(game.name)")
                    }.padding(.vertical, 5).tag(game.id)
                }
            }.id(library.query)
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
            Text("\(page.first)–\(page.last) of \(page.total) games").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Picker("Per page", selection: Binding(get: { library.query.pageSize }, set: { value in
                library.updateQuery { $0.pageSize = value }
            })) { ForEach([24, 48, 96], id: \.self) { Text("\($0)").tag($0) } }.frame(width: 140)
            Button("Previous", systemImage: "chevron.left") { library.goToPage(page.index - 1) }
                .disabled(page.index == 0 || library.loading)
            Text("\(page.index + 1) / \(page.count)").monospacedDigit().frame(minWidth: 64)
            Button("Next", systemImage: "chevron.right") { library.goToPage(page.index + 1) }
                .disabled(page.index + 1 >= page.count || library.loading)
        }
    }
}

private struct GameLibraryCard: View {
    let game: CloudGame
    let selected, favorite: Bool
    let select, toggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 8) {
                    AsyncImage(url: game.posterURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() }
                        else {
                            ZStack {
                                LinearGradient(colors: [.green.opacity(0.2), .gray.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                Image(systemName: "gamecontroller").font(.system(size: 32)).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity).frame(height: 190).clipped().accessibilityHidden(true)
                    Text(game.name).font(.headline).lineLimit(2).frame(height: 38, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Select \(game.name)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            HStack {
                Text(game.categories.first ?? "Cloud game").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Button(action: toggleFavorite) { Image(systemName: favorite ? "star.fill" : "star") }
                    .buttonStyle(.borderless).accessibilityLabel("\(favorite ? "Remove" : "Add") \(game.name) \(favorite ? "from" : "to") favorites")
            }.padding(10)
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.green : .clear, lineWidth: 2) }
    }
}

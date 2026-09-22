import Foundation

struct GameLibraryQuery: Hashable {
    enum Sort: String, CaseIterable { case ascending = "A–Z", descending = "Z–A" }
    enum Layout: String, CaseIterable { case grid = "Grid", list = "List" }
    var search = ""
    var category = ""
    var favoritesOnly = false
    var sort: Sort = .ascending
    var layout: Layout = .grid
    var pageSize = 24
    var pageIndex = 0

    struct Page {
        let games: [CloudGame]
        let total, index, count, first, last: Int
    }

    func page(in games: [CloudGame], favorites: Set<String>) -> Page {
        let terms = search.split(whereSeparator: \.isWhitespace).map(String.init)
        let matches = games.filter { game in
            (!favoritesOnly || favorites.contains(game.id)) &&
            (category.isEmpty || game.categories.contains(category)) &&
            terms.allSatisfy { term in
                game.name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order == .orderedSame { return lhs.id < rhs.id }
            return sort == .ascending ? order == .orderedAscending : order == .orderedDescending
        }
        let size = [24, 48, 96].contains(pageSize) ? pageSize : 24
        let count = max(1, (matches.count + size - 1) / size)
        let index = min(max(0, pageIndex), count - 1)
        let start = index * size, end = min(start + size, matches.count)
        return Page(games: Array(matches[start..<end]), total: matches.count, index: index,
                    count: count, first: matches.isEmpty ? 0 : start + 1, last: end)
    }
}

// Device-local title IDs only, independent from cloud account entitlements.
struct GameFavoritesStore {
    let defaults: UserDefaults
    private let key = "cloudLibrary.favoriteTitleIDs.v1"
    func load() -> Set<String> { Set((defaults.stringArray(forKey: key) ?? []).filter { !$0.isEmpty }) }
    func save(_ ids: Set<String>) { defaults.set(ids.sorted(), forKey: key) }
}

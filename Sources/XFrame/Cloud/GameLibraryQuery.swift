import Foundation

struct GameLibraryQuery: Hashable {
    enum Sort: String, CaseIterable { case ascending = "A–Z", descending = "Z–A" }
    enum Layout: String, CaseIterable { case grid = "Grid", list = "List" }
    enum Access: String, CaseIterable {
        case playable = "Playable games", gamePass = "Game Pass", free = "Free games", all = "All cloud games", unknown = "Access unverified"
    }
    var access: Access = .playable
    var search = ""
    var category = ""
    var favoritesOnly = false
    var recentlyPlayedOnly = false
    var sort: Sort = .ascending
    var layout: Layout = .grid
    var pageSize = 24
    var pageIndex = 0

    struct Page {
        let games: [CloudGame]
        let total, index, count, first, last: Int
    }

    func page(in games: [CloudGame], favorites: Set<String>, recentlyPlayed: [String] = []) -> Page {
        let terms = search.split(whereSeparator: \.isWhitespace).map(String.init)
        let recentRank = Dictionary(uniqueKeysWithValues: recentlyPlayed.enumerated().map { ($1, $0) })
        let matches = games.filter { game in
            matchesAccess(game.access) &&
            (!favoritesOnly || favorites.contains(game.id)) &&
            (!recentlyPlayedOnly || recentRank[game.id] != nil) &&
            (category.isEmpty || game.categories.contains(category)) &&
            terms.allSatisfy { term in
                game.name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }.sorted { lhs, rhs in
            if recentlyPlayedOnly, let l = recentRank[lhs.id], let r = recentRank[rhs.id], l != r {
                return l < r
            }
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

    private func matchesAccess(_ value: CloudGameAccess) -> Bool {
        switch access {
        case .playable: value.playable
        case .gamePass: value.playable && value.gamePass
        case .free: value.playable && value.free
        case .all: true
        case .unknown: value.entitled == nil
        }
    }
}

// Device-local title IDs only, independent from cloud account entitlements.
struct GameFavoritesStore {
    let defaults: UserDefaults
    private let key = "cloudLibrary.favoriteTitleIDs.v1"
    func load() -> Set<String> { Set((defaults.stringArray(forKey: key) ?? []).filter { !$0.isEmpty }) }
    func save(_ ids: Set<String>) { defaults.set(ids.sorted(), forKey: key) }
}

struct RecentlyPlayedStore {
    let defaults: UserDefaults
    private let key = "cloudLibrary.recentlyPlayedTitleIDs.v1"
    static let limit = 16
    func load() -> [String] { (defaults.stringArray(forKey: key) ?? []).filter { !$0.isEmpty } }
    @discardableResult
    func record(_ id: String, existing: [String]) -> [String] {
        guard !id.isEmpty else { return existing }
        var updated = existing.filter { $0 != id }
        updated.insert(id, at: 0)
        if updated.count > Self.limit { updated = Array(updated.prefix(Self.limit)) }
        defaults.set(updated, forKey: key)
        return updated
    }
}

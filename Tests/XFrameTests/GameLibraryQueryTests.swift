import Foundation
import Testing
@testable import XFrame

private func titles(_ count: Int) -> [CloudGame] {
    (0..<count).map { CloudGame(id: "id-\($0)", name: "Game \($0)", productID: nil,
        categories: [$0.isMultiple(of: 2) ? "Action" : "Puzzle"]) }
}

@Test func libraryPaginationCoversEachTitleExactlyOnce() {
    let games = titles(101)
    var query = GameLibraryQuery()
    var seen: [String] = []
    for index in 0..<5 {
        query.pageIndex = index
        let page = query.page(in: games, favorites: [])
        #expect(page.count == 5)
        #expect(page.index == index)
        #expect(page.first == index * 24 + 1)
        seen += page.games.map(\.id)
    }
    #expect(seen.count == games.count)
    #expect(Set(seen) == Set(games.map(\.id)))
    #expect(seen.prefix(3) == ["id-0", "id-1", "id-2"])
}

@Test func libraryFiltersComposeWithoutInventingEntitlements() {
    let games = [
        CloudGame(id: "a", name: "Café Racing 2", productID: nil, categories: ["Racing"]),
        CloudGame(id: "b", name: "CAFE Racing 10", productID: nil, categories: ["Racing"]),
        CloudGame(id: "c", name: "Racing Puzzle", productID: nil, categories: ["Puzzle"])
    ]
    var query = GameLibraryQuery()
    query.search = "  CAFE\n racing "
    #expect(query.page(in: games, favorites: []).games.map(\.id) == ["a", "b"])
    query.category = "Racing"
    query.favoritesOnly = true
    #expect(query.page(in: games, favorites: ["b", "c"]).games.map(\.id) == ["b"])
    query.category = "Unknown"
    #expect(query.page(in: games, favorites: ["b"]).total == 0)
}

@Test func libraryPaginationClampsEmptyChangedAndInvalidRequests() {
    var query = GameLibraryQuery()
    query.pageIndex = Int.max
    query.pageSize = Int.max
    let page = query.page(in: titles(25), favorites: [])
    #expect(page.index == 1 && page.first == 25 && page.last == 25)
    query.search = "does not exist"
    let empty = query.page(in: titles(25), favorites: [])
    #expect(empty.index == 0 && empty.count == 1 && empty.first == 0 && empty.last == 0)
    query.search = ""
    query.pageIndex = -10
    query.pageSize = 48
    #expect(query.page(in: titles(101), favorites: []).games.count == 48)
    query.sort = .descending
    #expect(query.page(in: titles(101), favorites: []).games.first?.name == "Game 100")
}

@Test func duplicateNamesKeepStableIdentityAndLargeCatalogPagesStayBounded() {
    let sameNames = [CloudGame(id: "b", name: "Same Game", productID: nil),
                     CloudGame(id: "a", name: "Same Game", productID: nil)]
    var query = GameLibraryQuery()
    #expect(query.page(in: sameNames, favorites: []).games.map(\.id) == ["a", "b"])
    query.sort = .descending
    #expect(query.page(in: sameNames, favorites: []).games.map(\.id) == ["a", "b"])
    let games = titles(2671)
    query.pageSize = 96
    query.pageIndex = 27
    let last = query.page(in: games, favorites: [])
    #expect(last.count == 28 && last.games.count == 79 && last.last == 2671)
    query.favoritesOnly = true
    let narrowed = query.page(in: games, favorites: ["id-2"])
    #expect(narrowed.index == 0 && narrowed.games.map(\.id) == ["id-2"])
}

@Test func favoriteIDsPersistLocallyAndRemainIndependentOfCatalog() throws {
    let suite = "XFrameTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = GameFavoritesStore(defaults: defaults)
    #expect(store.load().isEmpty)
    store.save(["a", "b"])
    #expect(GameFavoritesStore(defaults: defaults).load() == ["a", "b"])
    store.save([])
    #expect(store.load().isEmpty)
}

@Test func productArtworkUsesOnlyPublicMicrosoftHTTPSImages() throws {
    let metadata = try JSONDecoder().decode(CloudProductMetadata.self, from: Data(#"{"ProductTitle":"Example","Image_Poster":{"URL":"//store-images.s-microsoft.com/image/apps.example"},"Categories":["Action"],"PublisherName":"Example Publisher"}"#.utf8))
    #expect(metadata.posterURL?.absoluteString == "https://store-images.s-microsoft.com/image/apps.example")
    #expect(metadata.Categories == ["Action"])
    for url in ["http://store-images.s-microsoft.com/image", "file:///private/test", "https://evil.example/image",
                "https://store-images.s-microsoft.com.evil.example/image", "https://user:pass@store-images.s-microsoft.com/image"] {
        #expect(CloudProductMetadata.imageURL(url) == nil)
    }
    let fallback = try JSONDecoder().decode(CloudProductMetadata.self, from: Data(#"{"Image_Poster":{"URL":"http://invalid.example"},"Image_Tile":{"URL":"//store-images.s-microsoft.com/tile"}}"#.utf8))
    #expect(fallback.posterURL?.path == "/tile")
}

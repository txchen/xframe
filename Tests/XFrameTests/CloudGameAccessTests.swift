import Testing
@testable import XFrame

@Test func accountEvidenceControlsDefaultLibraryNotCatalogMembership() {
    let games = [
        CloudGame(id: "owned", name: "A", productID: nil, access: .init(entitled: true)),
        CloudGame(id: "pass", name: "B", productID: nil, access: .init(entitled: true, programs: ["GPULTIMATE"])),
        CloudGame(id: "denied", name: "C", productID: nil, access: .init(entitled: false, programs: ["GPULTIMATE"])),
        CloudGame(id: "unknown", name: "D", productID: nil),
        CloudGame(id: "free", name: "E", productID: nil, access: .init(entitled: true, free: true))
    ]
    var query = GameLibraryQuery()
    #expect(query.page(in: games, favorites: []).games.map(\.id) == ["owned", "pass", "free"])
    query.access = .gamePass
    #expect(query.page(in: games, favorites: []).games.map(\.id) == ["pass"])
    query.access = .free
    #expect(query.page(in: games, favorites: []).games.map(\.id) == ["free"])
    query.access = .unknown
    #expect(query.page(in: games, favorites: []).games.map(\.id) == ["unknown"])
    query.access = .all
    #expect(query.page(in: games, favorites: []).total == 5)
    #expect(CloudGameAccess(entitled: false, free: true).playable == false)
    #expect(CloudGameAccess(entitled: true).label == "Playable")
    #expect(CloudGameAccess().label == "Access unverified")
}

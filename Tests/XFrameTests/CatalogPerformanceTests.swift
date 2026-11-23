import Foundation
import Testing
@testable import XFrame

private final class CatalogStubScript: @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @Sendable (URLRequest, Data) -> (Int, String, TimeInterval)
    private var recordedRequests: [(URL, Data)] = []

    init(_ handler: @escaping @Sendable (URLRequest, Data) -> (Int, String, TimeInterval)) {
        self.handler = handler
    }

    func handle(_ request: URLRequest) -> (Int, String, TimeInterval) {
        let body = Self.readBody(request)
        lock.withLock {
            if let url = request.url { recordedRequests.append((url, body)) }
        }
        return handler(request, body)
    }

    var requests: [(URL, Data)] { lock.withLock { recordedRequests } }

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

private final class CatalogStubRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var scripts: [String: CatalogStubScript] = [:]
    func set(_ script: CatalogStubScript, id: String) { lock.withLock { scripts[id] = script } }
    func get(_ id: String) -> CatalogStubScript? { lock.withLock { scripts[id] } }
    func remove(_ id: String) { _ = lock.withLock { scripts.removeValue(forKey: id) } }
}

private final class CatalogStubProtocol: URLProtocol, @unchecked Sendable {
    static let router = CatalogStubRouter()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    private var work: Task<Void, Never>?

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Catalog-Test-ID") ?? ""
        guard let script = Self.router.get(id) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, json, delay) = script.handle(request)
        if delay > 0 {
            work = Task { @Sendable [self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                complete(status: status, json: json)
            }
        } else {
            complete(status: status, json: json)
        }
    }

    private func complete(status: Int, json: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { work?.cancel() }
}

private final class CatalogHarness {
    let script: CatalogStubScript
    let session: URLSession
    private let id = UUID().uuidString

    init(_ handler: @escaping @Sendable (URLRequest, Data) -> (Int, String, TimeInterval)) {
        let script = CatalogStubScript(handler)
        self.script = script
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CatalogStubProtocol.self]
        config.httpAdditionalHeaders = ["X-Catalog-Test-ID": id]
        self.session = URLSession(configuration: config)
        CatalogStubProtocol.router.set(script, id: id)
    }

    deinit {
        session.invalidateAndCancel()
        CatalogStubProtocol.router.remove(id)
    }
}

private let sampleCloudTokenJSON = #"{"gsToken":"test-cloud","durationInSeconds":14400,"market":"US","offeringSettings":{"regions":[{"name":"Test Region","baseUri":"https://test.gssv-play-prod.xboxlive.com/","isDefault":true}]}}"#

private func makeTempCacheDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("XFrameCatalogCacheTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func fileProductMetadataCachePersistsSeparatesMarketsAndExpiresTTL() throws {
    let dir = try makeTempCacheDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    let currentDate = Date(timeIntervalSince1970: 1_700_000_000)
    let first = FileProductMetadataCache(directory: dir, ttl: 60, now: { currentDate })
    let metadataUS = CloudProductMetadata(
        ProductTitle: "Halo Infinite",
        Image_Poster: .init(URL: "//store-images.s-microsoft.com/image/halo"),
        Image_Tile: nil,
        Categories: ["Shooter"],
        PublisherName: "Xbox Game Studios"
    )
    let metadataJP = CloudProductMetadata(
        ProductTitle: "Halo JP",
        Image_Poster: nil,
        Image_Tile: nil,
        Categories: ["Shooter"],
        PublisherName: "Xbox Game Studios"
    )
    first.save(["P1": metadataUS], market: "US")
    first.save(["P1": metadataJP], market: "JP")

    // Re-open from disk with a new cache instance.
    let second = FileProductMetadataCache(directory: dir, ttl: 60, now: { currentDate.addingTimeInterval(30) })
    #expect(second.load(market: "US") == ["P1": metadataUS])
    #expect(second.load(market: "JP") == ["P1": metadataJP])
    #expect(second.load(market: "GB").isEmpty)

    // Expired entries are filtered out.
    let expired = FileProductMetadataCache(directory: dir, ttl: 60, now: { currentDate.addingTimeInterval(120) })
    #expect(expired.load(market: "US").isEmpty)

    // Corrupted cache file degrades safely to empty.
    let corruptFile = dir.appendingPathComponent("catalog-metadata-DE.json")
    try Data("not-json".utf8).write(to: corruptFile)
    #expect(second.load(market: "DE").isEmpty)

    // Market sanitization rejects path traversal characters.
    #expect(FileProductMetadataCache.sanitizedMarket("../us?bad") == "USBAD")
    #expect(FileProductMetadataCache.sanitizedMarket("en-US") == "EN-US")
    #expect(FileProductMetadataCache.sanitizedMarket("///") == "US")
}

@Test func cloudServiceSkipsCatalogRequestsOnCacheHitAndUsesLiveEntitlements() async throws {
    let dir = try makeTempCacheDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = FileProductMetadataCache(directory: dir)
    cache.save([
        "P1": CloudProductMetadata(
            ProductTitle: "Cached Halo",
            Image_Poster: .init(URL: "https://store-images.s-microsoft.com/image/p1"),
            Image_Tile: nil,
            Categories: ["Action"],
            PublisherName: "Xbox"
        )
    ], market: "US")

    let harness = CatalogHarness { request, _ in
        if request.url?.path == "/v2/titles" {
            return (200, #"{"results":[{"titleId":"T1","details":{"productId":"P1","name":"Raw T1","hasEntitlement":false,"programs":["GPULTIMATE"]}}]}"#, 0)
        }
        return (500, "{}", 0)
    }
    let credential = try JSONDecoder().decode(CloudToken.self, from: Data(sampleCloudTokenJSON.utf8))
    let service = try CloudService(credential: credential, expires: Date().addingTimeInterval(3600),
                                   session: harness.session, metadataCache: cache)
    let games = try await service.games()
    #expect(games.count == 1)
    #expect(games[0].name == "Cached Halo")
    #expect(games[0].posterURL == URL(string: "https://store-images.s-microsoft.com/image/p1"))
    // Entitlement must always come from live v2/titles, never cached.
    #expect(games[0].access.entitled == false)
    #expect(!games[0].access.playable)
    // Zero requests made to catalog.gamepass.com.
    #expect(harness.script.requests.filter { $0.0.host == "catalog.gamepass.com" }.isEmpty)
}

@Test func cloudServiceFetchesOnlyMissingProductsProgressivelyAndToleratesBatchFailure() async throws {
    let dir = try makeTempCacheDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = FileProductMetadataCache(directory: dir)
    cache.save([
        "P0": CloudProductMetadata(ProductTitle: "Cached Zero", Image_Poster: nil, Image_Tile: nil, Categories: nil, PublisherName: nil)
    ], market: "US")

    // 102 missing products (P1...P102) -> 2 batches (100 + 2). P102 is prioritized into batch 1.
    let titlesJSON: String = {
        var items: [String] = [
            #"{"titleId":"T0","details":{"productId":"P0","name":"Raw 0","hasEntitlement":true}}"#
        ]
        for i in 1...102 {
            let name = String(format: "Title %03d", i)
            items.append(#"{"titleId":"T\#(i)","details":{"productId":"P\#(i)","name":"\#(name)","hasEntitlement":true}}"#)
        }
        return #"{"results":[\#(items.joined(separator: ","))]}"#
    }()

    let harness = CatalogHarness { request, body in
        if request.url?.path == "/v2/titles" {
            return (200, titlesJSON, 0)
        }
        if request.url?.host == "catalog.gamepass.com" {
            let json = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            let ids = (json["Products"] as? [String]) ?? []
            if ids.count < 100 {
                // Simulate second batch failing: must degrade gracefully instead of failing entire catalog.
                return (503, "{}", 0.05)
            }
            var products: [String: [String: Any]] = [:]
            for id in ids {
                products[id] = ["ProductTitle": "Hydrated \(id)"]
            }
            let data = (try? JSONSerialization.data(withJSONObject: ["Products": products])) ?? Data()
            return (200, String(decoding: data, as: UTF8.self), 0.05)
        }
        return (500, "{}", 0)
    }

    let credential = try JSONDecoder().decode(CloudToken.self, from: Data(sampleCloudTokenJSON.utf8))
    let service = try CloudService(credential: credential, expires: Date().addingTimeInterval(3600),
                                   session: harness.session, metadataCache: cache)

    actor UpdateRecorder {
        var snapshots: [[CloudGame]] = []
        func record(_ games: [CloudGame]) { snapshots.append(games) }
    }
    let recorder = UpdateRecorder()

    let finalGames = try await service.loadGames(prioritizing: ["P102"]) { partial in
        await recorder.record(partial)
    }

    let snapshots = await recorder.snapshots
    // At least initial v2/titles snapshot + hydrated batch snapshot.
    #expect(snapshots.count >= 2)
    // First snapshot immediately has cached P0 and fallback name for P102.
    #expect(snapshots[0].first { $0.id == "T0" }?.name == "Cached Zero")
    #expect(snapshots[0].first { $0.id == "T102" }?.name == "Title 102")
    // Final result has hydrated P102 (prioritized into batch 1) and degrades gracefully on batch 2.
    #expect(finalGames.count == 103)
    #expect(finalGames.first { $0.id == "T102" }?.name == "Hydrated P102")
    // P0 was cached, so it must never have been requested from catalog.gamepass.com.
    let catalogBodies = harness.script.requests
        .filter { $0.0.host == "catalog.gamepass.com" }
        .compactMap { (try? JSONSerialization.jsonObject(with: $0.1) as? [String: Any])?["Products"] as? [String] }
    #expect(catalogBodies.count == 2)
    #expect(!catalogBodies.flatMap { $0 }.contains("P0"))
    // Prioritized P102 must be in the first batch.
    let batchWithPriority = catalogBodies.first { $0.contains("P102") }
    #expect(batchWithPriority?.count == 100)
    // Newly hydrated products were saved to cache.
    let cachedAfter = cache.load(market: "US")
    #expect(cachedAfter["P102"]?.ProductTitle == "Hydrated P102")
}

private actor ProgressiveFakeCloud: CloudServing {
    let initial: [CloudGame]
    let final: [CloudGame]
    let delay: Duration
    let fail: Bool

    init(initial: [CloudGame], final: [CloudGame], delay: Duration = .milliseconds(80), fail: Bool = false) {
        self.initial = initial
        self.final = final
        self.delay = delay
        self.fail = fail
    }

    func games() async throws -> [CloudGame] {
        if fail { throw CloudError.network }
        return final
    }

    func loadGames(
        prioritizing priorityProductIDs: Set<String>,
        onUpdate: @Sendable ([CloudGame]) async -> Void
    ) async throws -> [CloudGame] {
        if fail { throw CloudError.network }
        await onUpdate(initial)
        try await Task.sleep(for: delay)
        await onUpdate(final)
        return final
    }

    func create(title: String, preferences: CloudStreamPreferences) async throws -> URL {
        URL(string: "https://test.gssv-play-prod.xboxlive.com/v5/sessions/cloud/s")!
    }
    func state(at: URL) async throws -> CloudSessionState { .init(state: "Provisioned", transferUri: nil) }
    func configuration(at: URL) async throws {}
    func connect(at: URL) async throws {}
    func end(at: URL) async throws {}
}

@Test @MainActor func cloudLibraryRendersProgressivelyAndKeepsGamesVisibleDuringRefresh() async throws {
    let raw = CloudGame(id: "G1", name: "Raw G1", productID: "P1", access: .init(entitled: true))
    let hydrated = CloudGame(id: "G1", name: "Full Game One", productID: "P1", access: .init(entitled: true))
    let library = CloudLibrary()

    library.load(using: ProgressiveFakeCloud(initial: [raw], final: [hydrated], delay: .milliseconds(120)))
    // Wait for initial progressive update while load is still in progress.
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !library.catalogLoaded && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(library.catalogLoaded)
    #expect(library.loading)
    #expect(library.games == [raw])

    while library.loading && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(library.games == [hydrated])
    #expect(library.gameLoadAction == .refresh)

    // Refreshing must keep existing games visible instead of blanking the catalog.
    library.load(using: ProgressiveFakeCloud(initial: [hydrated], final: [hydrated], delay: .milliseconds(80)))
    #expect(library.loading)
    #expect(library.catalogLoaded)
    #expect(library.games == [hydrated])
    while library.loading && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }

    // Failed refresh keeps existing catalog visible but surfaces Retry button.
    library.load(using: ProgressiveFakeCloud(initial: [], final: [], fail: true))
    while library.loading && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(library.games == [hydrated])
    #expect(library.gameLoadAction == .retry)
}

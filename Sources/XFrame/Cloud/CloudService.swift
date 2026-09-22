import Foundation

struct CloudGame: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let productID: String?
    let posterURL: URL?
    let categories: [String]
    let publisher: String?

    init(id: String, name: String, productID: String?, posterURL: URL? = nil,
         categories: [String] = [], publisher: String? = nil) {
        self.id = id; self.name = name; self.productID = productID
        self.posterURL = posterURL; self.categories = categories; self.publisher = publisher
    }
}

struct CloudProductMetadata: Decodable, Sendable {
    struct Image: Decodable, Sendable { let URL: String? }
    let ProductTitle: String?
    let Image_Poster: Image?
    let Image_Tile: Image?
    let Categories: [String]?
    let PublisherName: String?

    var posterURL: URL? {
        [Image_Poster?.URL, Image_Tile?.URL].compactMap { $0 }.compactMap(Self.imageURL).first
    }
    static func imageURL(_ raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value.hasPrefix("//") ? "https:" + value : value),
              url.scheme == "https", url.host == "store-images.s-microsoft.com",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil else { return nil }
        return url
    }
}

struct CloudSessionState: Decodable, Sendable {
    let state: String
    let transferUri: URL?
}

enum CloudError: Error, LocalizedError {
    case response, http(Int), network, expired, failed, unsupportedState, timeout
    var errorDescription: String? {
        switch self {
        case .response: "The cloud service returned an unsupported response."
        case .http(let code): "Cloud request failed (HTTP \(code)). Check account access or try again."
        case .network: "Cannot reach the cloud service. Check your connection."
        case .expired: "Cloud credentials expired. End any session, then check account access again."
        case .failed: "The cloud session failed to start."
        case .unsupportedState: "The service requires a session step this version does not support."
        case .timeout: "The cloud session did not become ready within 10 minutes."
        }
    }
}

protocol CloudServing: Sendable {
    func games() async throws -> [CloudGame]
    func create(title: String) async throws -> URL
    func state(at: URL) async throws -> CloudSessionState
    func configuration(at: URL) async throws
    func connect(at: URL) async throws
    func end(at: URL) async throws
}

struct CloudService: CloudServing {
    let regionName: String
    private let token: String
    private let host: URL
    private let expires: Date
    private let market: String
    private let session: URLSession
    private let transferToken: @Sendable () async throws -> String

    init(credential: CloudToken, expires: Date, regionName: String? = nil, session: URLSession? = nil,
         transferToken: @escaping @Sendable () async throws -> String = { throw CloudError.expired }) throws {
        let regions = credential.offeringSettings.regions
        let selected = regionName.map { name in regions.first(where: { $0.name == name }) }
            ?? (regions.first(where: { $0.isDefault == true }) ?? regions.first)
        guard let region = selected,
              Self.trusted(region.baseUri) else { throw CloudError.response }
        self.regionName = region.name
        host = region.baseUri
        token = credential.gsToken
        market = credential.market ?? "US"
        self.expires = expires
        self.transferToken = transferToken
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        self.session = session ?? URLSession(configuration: config, delegate: AuthRedirectPolicy(), delegateQueue: nil)
    }

    static func trusted(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.port == nil &&
        url.query == nil && url.fragment == nil && (url.host ?? "").hasSuffix(".xboxlive.com")
    }

    static func sessionURL(_ path: String, relativeTo host: URL) throws -> URL {
        guard let url = URL(string: path, relativeTo: host)?.absoluteURL, trusted(url),
              url.path.hasPrefix("/v5/sessions/cloud/"),
              url.path.split(separator: "/").count == 4,
              !["play", "active", ".", ".."].contains(url.lastPathComponent) else { throw CloudError.response }
        return url
    }

    func games() async throws -> [CloudGame] {
        struct Titles: Decodable { let results: [Title] }
        struct Title: Decodable {
            struct Details: Decodable { let productId: String?; let name: String? }
            let titleId: String
            let details: Details?
        }
        let data = try await request(host.appendingPathComponent("v2/titles"))
        let titles = try decode(Titles.self, data).results
        let ids = Array(Set(titles.compactMap { $0.details?.productId })).sorted()
        let batches = stride(from: 0, to: ids.count, by: 100).map { Array(ids[$0..<min($0 + 100, ids.count)]) }
        let products = try await withThrowingTaskGroup(of: [String: CloudProductMetadata].self) { group in
            var next = 0
            for _ in 0..<min(4, batches.count) {
                let batch = batches[next]; next += 1
                group.addTask { try await productMetadata(batch) }
            }
            var result: [String: CloudProductMetadata] = [:]
            while let batch = try await group.next() {
                result.merge(batch) { first, _ in first }
                if next < batches.count {
                    let batch = batches[next]; next += 1
                    group.addTask { try await productMetadata(batch) }
                }
            }
            return result
        }
        var seen = Set<String>()
        return titles.filter { !$0.titleId.isEmpty && seen.insert($0.titleId).inserted }.map {
            let metadata = products[$0.details?.productId ?? ""]
            return CloudGame(id: $0.titleId, name: metadata?.ProductTitle ?? $0.details?.name ?? $0.titleId,
                      productID: $0.details?.productId, posterURL: metadata?.posterURL,
                      categories: Array(Set((metadata?.Categories ?? []).filter { !$0.isEmpty })).sorted(),
                      publisher: metadata?.PublisherName)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func productMetadata(_ ids: [String]) async throws -> [String: CloudProductMetadata] {
            // Metadata is public: never send the streaming bearer token to the catalog.
            try Task.checkCancellation()
            var url = URLComponents(string: "https://catalog.gamepass.com/v3/products")!
            url.queryItems = [.init(name: "market", value: market), .init(name: "language", value: "en-US"),
                             .init(name: "hydration", value: "RemoteLowJade0")]
            let body = try JSONSerialization.data(withJSONObject: ["Products": ids])
            struct Products: Decodable {
                let Products: [String: CloudProductMetadata]
            }
            let result = try await request(url.url!, method: "POST", body: body, authenticated: false,
                headers: ["ms-cv": "0", "calling-app-name": "Xbox Cloud Gaming Web", "calling-app-version": "24.17.63"])
            return try decode(Products.self, result).Products
    }

    func create(title: String) async throws -> URL {
        let body: [String: Any] = ["clientSessionId": UUID().uuidString, "titleId": title,
            "systemUpdateGroup": "", "serverId": "", "fallbackRegionNames": [String](),
            "settings": ["nanoVersion": "V3;WebrtcTransport.dll", "enableTextToSpeech": false,
                "highContrast": 0, "locale": "en-US", "useIceConnection": false,
                "timezoneOffsetMinutes": -TimeZone.current.secondsFromGMT() / 60, "sdkType": "web", "osName": "macos"]]
        let device: [String: Any] = ["appInfo": ["env": ["clientAppId": "www.xbox.com", "clientAppType": "browser",
            "clientAppVersion": "29.9.35", "clientSdkVersion": "10.6.8", "httpEnvironment": "prod", "sdkInstallId": ""]],
            "dev": ["hw": ["make": "Apple", "model": "Mac", "platformType": "desktop", "sdktype": "web"],
                    "os": ["name": "macos", "ver": "27", "platform": "desktop"],
                    "displayInfo": ["dimensions": ["widthInPixels": 1920, "heightInPixels": 1080],
                                    "pixelDensity": ["dpiX": 1, "dpiY": 1]]]]
        let deviceHeader = String(decoding: try JSONSerialization.data(withJSONObject: device), as: UTF8.self)
        let data = try await request(host.appendingPathComponent("v5/sessions/cloud/play"), method: "POST",
            body: JSONSerialization.data(withJSONObject: body), headers: ["X-MS-Device-Info": deviceHeader])
        struct Created: Decodable { let sessionPath: String }
        return try Self.sessionURL(decode(Created.self, data).sessionPath, relativeTo: host)
    }

    func state(at url: URL) async throws -> CloudSessionState {
        try decode(CloudSessionState.self, await request(url.appendingPathComponent("state")))
    }

    func configuration(at url: URL) async throws {
        let data = try await request(url.appendingPathComponent("configuration"))
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw CloudError.response }
    }

    func connect(at url: URL) async throws {
        let token = try await transferToken()
        _ = try await request(url.appendingPathComponent("connect"), method: "POST",
                              body: JSONSerialization.data(withJSONObject: ["userToken": token]))
    }

    func end(at url: URL) async throws {
        do { _ = try await request(url, method: "DELETE") }
        catch CloudError.http(let status) where status == 404 || status == 410 { return }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw CloudError.response }
    }

    func request(_ url: URL, method: String = "GET", body: Data? = nil,
                         authenticated: Bool = true, headers: [String: String] = [:]) async throws -> Data {
        if authenticated {
            guard Self.trusted(url) else { throw CloudError.response }
            // Always attempt cleanup, even near credential expiry.
            guard method == "DELETE" || Date() < expires else { throw CloudError.expired }
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if authenticated { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let result: (Data, URLResponse)
        do { result = try await session.data(for: request) }
        catch { if Task.isCancelled { throw CancellationError() }; throw CloudError.network }
        guard let response = result.1 as? HTTPURLResponse else { throw CloudError.response }
        guard (200..<300).contains(response.statusCode) else { throw CloudError.http(response.statusCode) }
        return result.0
    }
}

import Foundation

struct CloudGame: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let productID: String?
    let posterURL: URL?
    let categories: [String]
    let publisher: String?
    var access: CloudGameAccess

    init(id: String, name: String, productID: String?, posterURL: URL? = nil,
         categories: [String] = [], publisher: String? = nil, access: CloudGameAccess = .init()) {
        self.id = id; self.name = name; self.productID = productID
        self.posterURL = posterURL; self.categories = categories; self.publisher = publisher
        self.access = access
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
    case rejected(Int, String)
    var errorDescription: String? {
        switch self {
        case .response: "The cloud service returned an unsupported response."
        case .http(let code): "Cloud request failed (HTTP \(code)). Check account access or try again."
        case .rejected(let status, let code): "Cloud request failed (HTTP \(status), service code: \(code))."
        case .network: "Cannot reach the cloud service. Check your connection."
        case .expired: "Cloud credentials expired. End any session, then check account access again."
        case .failed: "The cloud session failed to start."
        case .unsupportedState: "The service requires a session step this version does not support."
        case .timeout: "The cloud session did not become ready within 10 minutes."
        }
    }
}

protocol SessionServing: Sendable {
    func create(title: String, preferences: CloudStreamPreferences) async throws -> URL
    func state(at: URL) async throws -> CloudSessionState
    func configuration(at: URL) async throws
    func connect(at: URL) async throws
    func end(at: URL) async throws
}

protocol CloudServing: SessionServing {
    func games() async throws -> [CloudGame]
}

struct CloudService: CloudServing {
    enum Source: String, Sendable { case cloud, home }
    let regionName: String
    let source: Source
    private let token: String
    private let host: URL
    var baseURL: URL { host }
    private let expires: Date
    private let market: String
    private let session: URLSession
    private let transferToken: @Sendable () async throws -> String

    init(credential: CloudToken, expires: Date, regionName: String? = nil, source: Source = .cloud,
         session: URLSession? = nil,
         transferToken: @escaping @Sendable () async throws -> String = { throw CloudError.expired }) throws {
        let regions = credential.offeringSettings.regions
        let selected = regionName.map { name in regions.first(where: { $0.name == name }) }
            ?? (regions.first(where: { $0.isDefault == true }) ?? regions.first)
        guard let region = selected,
              Self.trusted(region.baseUri) else { throw CloudError.response }
        self.regionName = region.name
        self.source = source
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

    static func sessionURL(_ path: String, relativeTo host: URL, source: Source = .cloud) throws -> URL {
        guard let url = URL(string: path, relativeTo: host)?.absoluteURL, trusted(url),
              url.path.hasPrefix("/v5/sessions/\(source.rawValue)/"),
              url.path.split(separator: "/").count == 4,
              !["play", "active", ".", ".."].contains(url.lastPathComponent) else { throw CloudError.response }
        return url
    }

    func games() async throws -> [CloudGame] {
        struct Titles: Decodable { let results: [Title] }
        struct Title: Decodable {
            struct Details: Decodable {
                let productId: String?; let name: String?
                let hasEntitlement: Bool?
                let programs: [String]?
                let isFreeInStore: Bool?
            }
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
                      publisher: metadata?.PublisherName,
                      access: CloudGameAccess(entitled: $0.details?.hasEntitlement,
                          programs: $0.details?.programs ?? [], free: $0.details?.isFreeInStore == true))
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

    func create(title: String, preferences: CloudStreamPreferences = .init()) async throws -> URL {
        let home = source == .home
        let body: [String: Any] = ["clientSessionId": UUID().uuidString, "titleId": home ? "" : title,
            "systemUpdateGroup": "", "serverId": home ? title : "", "fallbackRegionNames": [String](),
            "settings": ["nanoVersion": "V3;WebrtcTransport.dll", "enableTextToSpeech": false,
                "highContrast": 0, "locale": home ? "en-US" : preferences.language.rawValue, "useIceConnection": false,
                "timezoneOffsetMinutes": -TimeZone.current.secondsFromGMT() / 60, "sdkType": "web",
                "osName": home ? "windows" : preferences.quality.osName]]
        let hq = !home && preferences.quality == .hq
        var hardware: [String: Any] = [
            "hw": ["make": hq || home ? "Microsoft" : "Apple", "model": hq || home ? "unknown" : "Mac", "platformType": "desktop", "sdktype": "web"],
            "os": ["name": home ? "windows" : preferences.quality.osName,
                    "ver": home || hq ? "22631.2715" : "27", "platform": "desktop"],
            "displayInfo": ["dimensions": ["widthInPixels": home ? 1920 : preferences.quality.width,
                                           "heightInPixels": home ? 1080 : preferences.quality.height],
                            "pixelDensity": ["dpiX": 1, "dpiY": 1]]]
        if hq || home { hardware["browser"] = ["browserName": "edge", "browserVersion": "140.0.3485.66"] }
        let device: [String: Any] = ["appInfo": ["env": ["clientAppId": "www.xbox.com", "clientAppType": "browser",
            "clientAppVersion": "29.9.35", "clientSdkVersion": "10.6.8", "httpEnvironment": "prod", "sdkInstallId": ""]],
            "dev": hardware]
        let deviceHeader = String(decoding: try JSONSerialization.data(withJSONObject: device), as: UTF8.self)
        let data = try await request(host.appendingPathComponent("v5/sessions/\(source.rawValue)/play"), method: "POST",
            body: JSONSerialization.data(withJSONObject: body), headers: ["X-MS-Device-Info": deviceHeader])
        struct Created: Decodable { let sessionPath: String }
        return try Self.sessionURL(decode(Created.self, data).sessionPath, relativeTo: host, source: source)
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
            var trustedURL = url
            let consoleList = source == .home && url.path == "/v6/servers/home" && url.query == "mr=50"
            if consoleList { trustedURL = URL(string: String(url.absoluteString.split(separator: "?")[0]))! }
            guard Self.trusted(trustedURL), url.query == nil || consoleList else { throw CloudError.response }
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
        guard (200..<300).contains(response.statusCode) else {
            if method == "POST", url.path.hasSuffix("/sessions/cloud/play"),
               let code = Self.failureCode(result.0) {
                throw CloudError.rejected(response.statusCode, code)
            }
            throw CloudError.http(response.statusCode)
        }
        return result.0
    }

    // Never surface arbitrary messages, IDs, headers, or raw authenticated responses.
    static func failureCode(_ data: Data) -> String? {
        guard data.count <= 65_536,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let nested = object["error"] as? [String: Any]
        guard let code = (object["code"] ?? nested?["code"]) as? String,
              !code.isEmpty, code.count <= 64,
              code.unicodeScalars.allSatisfy({ CharacterSet.letters.union(CharacterSet(charactersIn: "_-")).contains($0) }),
              code.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
        return code
    }
}

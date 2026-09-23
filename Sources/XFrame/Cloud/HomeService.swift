import Foundation

struct HomeConsole: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let model: String
    let powerState: String
    var local: Bool = false
    var inHomeService: Bool = false
    var homeServiceChecked: Bool = true
    var standby: Bool { powerState == "ConnectedStandby" }
}

protocol HomeServing: SessionServing, CloudSignaling {
    func consoles() async throws -> [HomeConsole]
    func wake(_ id: String) async throws
}

struct HomeService: HomeServing {
    let stream: CloudService?
    private let webToken: String
    private let userHash: String
    private let session: URLSession

    init(credential: CloudToken?, expires: Date, webToken: String, userHash: String,
         session: URLSession? = nil,
         transferToken: @escaping @Sendable () async throws -> String = { throw CloudError.expired }) throws {
        stream = try credential.map {
            try CloudService(credential: $0, expires: expires, source: .home,
                             session: session, transferToken: transferToken)
        }
        self.webToken = webToken
        self.userHash = userHash
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        self.session = session ?? URLSession(configuration: config, delegate: AuthRedirectPolicy(), delegateQueue: nil)
    }

    func consoles() async throws -> [HomeConsole] {
        // XCCS is the complete associated-device list; xHome marks streamable consoles.
        let associated = try Self.parse(try await webRequest("lists/devices?queryCurrentDevice=false&includeStorageDevices=true",
                                                            contractVersion: "2"), key: "result", streamable: false)
        let home: [HomeConsole]?
        if let stream {
            var listURL = URLComponents(url: stream.baseURL.appendingPathComponent("v6/servers/home"), resolvingAgainstBaseURL: false)!
            listURL.queryItems = [.init(name: "mr", value: "50")]
            do {
                let device: [String: Any] = [
                    "appInfo": ["env": ["clientAppId": "www.xbox.com", "clientAppType": "browser",
                        "clientAppVersion": "29.9.35", "clientSdkVersion": "10.6.8",
                        "httpEnvironment": "prod", "sdkInstallId": ""]],
                    "dev": ["hw": ["make": "Microsoft", "model": "unknown", "sdktype": "web"],
                        "os": ["name": "windows", "ver": "22631.2715", "platform": "desktop"],
                        "displayInfo": ["dimensions": ["widthInPixels": 1920, "heightInPixels": 1080],
                                        "pixelDensity": ["dpiX": 1, "dpiY": 1]]]]
                let header = String(decoding: try JSONSerialization.data(withJSONObject: device), as: UTF8.self)
                home = try Self.parse(try await stream.request(listURL.url!, headers: ["X-MS-Device-Info": header]),
                                      key: "results", streamable: true)
            }
            catch { home = nil }
        } else { home = nil }
        var result: [String: HomeConsole] = [:]
        for var item in associated {
            item.homeServiceChecked = home != nil
            result[item.id.lowercased()] = item
        }
        for item in home ?? [] {
            let key = item.id.lowercased()
            let old = result[key]
            result[key] = HomeConsole(id: item.id, name: item.name.isEmpty ? old?.name ?? item.id : item.name,
                model: item.model.isEmpty ? old?.model ?? "Xbox" : item.model,
                powerState: item.powerState.isEmpty ? old?.powerState ?? "Unknown" : item.powerState,
                inHomeService: true)
        }
        return result.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func parse(_ data: Data, key: String, streamable: Bool) throws -> [HomeConsole] {
        guard data.count < 2_000_000,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root[key] as? [[String: Any]] else { throw CloudError.response }
        return rows.compactMap { row in
            guard let id = (row["serverId"] ?? row["id"]) as? String,
                  !id.isEmpty, id.count < 256 else { return nil }
            let name = (row["deviceName"] ?? row["name"]) as? String ?? "Xbox console"
            let model = (row["consoleType"] ?? row["model"] ?? row["deviceType"]) as? String ?? "Xbox"
            let power = row["powerState"] as? String ?? "Unknown"
            return HomeConsole(id: id, name: String(name.prefix(100)), model: String(model.prefix(80)),
                               powerState: String(power.prefix(80)), inHomeService: streamable)
        }
    }

    func wake(_ id: String) async throws {
        guard !id.isEmpty, id.count < 256 else { throw CloudError.response }
        let payload: [String: Any] = ["destination": "Xbox", "type": "Power", "command": "WakeUp",
            "sessionId": UUID().uuidString, "sourceId": "com.microsoft.smartglass", "parameters": [Any](),
            "linkedXboxId": id]
        let data = try await webRequest("commands", method: "POST", body: JSONSerialization.data(withJSONObject: payload))
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["result"] != nil else { throw CloudError.response }
    }

    private func webRequest(_ path: String, method: String = "GET", body: Data? = nil,
                            contractVersion: String = "4") async throws -> Data {
        guard let url = URL(string: "https://xccs.xboxlive.com/" + path),
              url.host == "xccs.xboxlive.com", url.scheme == "https" else { throw CloudError.response }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("XBL3.0 x=\(userHash);\(webToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(contractVersion, forHTTPHeaderField: "x-xbl-contract-version")
        request.setValue("XboxApp", forHTTPHeaderField: "x-xbl-client-name")
        request.setValue("UWA", forHTTPHeaderField: "x-xbl-client-type")
        request.setValue("39.39.22001.0", forHTTPHeaderField: "x-xbl-client-version")
        request.setValue("RemoteManagement", forHTTPHeaderField: "skillplatform")
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw CloudError.response }
            guard (200..<300).contains(response.statusCode) else { throw CloudError.http(response.statusCode) }
            return data
        } catch let error as CloudError { throw error }
        catch { throw CloudError.network }
    }

    func create(title: String, preferences: CloudStreamPreferences) async throws -> URL {
        guard let stream else { throw CloudError.expired }
        return try await stream.create(title: title, preferences: preferences)
    }
    func state(at url: URL) async throws -> CloudSessionState {
        guard let stream else { throw CloudError.expired }
        return try await stream.state(at: url)
    }
    func configuration(at url: URL) async throws {
        guard let stream else { throw CloudError.expired }
        try await stream.configuration(at: url)
    }
    func connect(at url: URL) async throws {
        guard let stream else { throw CloudError.expired }
        try await stream.connect(at: url)
    }
    func end(at url: URL) async throws {
        guard let stream else { throw CloudError.expired }
        try await stream.end(at: url)
    }
    func exchangeSDP(at url: URL, offer: String) async throws -> String {
        guard let stream else { throw CloudError.expired }
        return try await stream.exchangeSDP(at: url, offer: offer)
    }
    func exchangeICE(at url: URL, candidates: [CloudICECandidate]) async throws -> [CloudICECandidate] {
        guard let stream else { throw CloudError.expired }
        return try await stream.exchangeICE(at: url, candidates: candidates)
    }
    func keepAlive(at url: URL) async throws {
        guard let stream else { throw CloudError.expired }
        try await stream.keepAlive(at: url)
    }
    func keepAliveInterval(at url: URL) async throws -> Double {
        guard let stream else { throw CloudError.expired }
        return try await stream.keepAliveInterval(at: url)
    }
}

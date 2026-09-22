import Foundation

struct DeviceAuthorization: Decodable, Sendable {
    let device_code: String
    let user_code: String
    let verification_uri: URL
    let expires_in: Int
    let interval: Int?

    var pollingInterval: Int { max(5, interval ?? 5) }
}

struct MicrosoftToken: Decodable, Sendable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

struct ConsoleTransferToken: Decodable, Sendable {
    let access_token: String
    let refresh_token: String?
}

struct XboxToken: Decodable, Sendable {
    struct Claims: Decodable, Sendable {
        struct User: Decodable, Sendable {
            let gtg: String?
            let mgt: String?
            let uhs: String?
        }
        let xui: [User]?
    }
    let Token: String
    let DisplayClaims: Claims?
    var gamertag: String? { DisplayClaims?.xui?.first?.gtg ?? DisplayClaims?.xui?.first?.mgt }
}

struct CloudToken: Decodable, Sendable {
    struct Settings: Decodable, Sendable {
        struct Region: Decodable, Sendable {
            let name: String
            let baseUri: URL
            let isDefault: Bool?
        }
        let regions: [Region]
    }
    let gsToken: String
    let durationInSeconds: Int
    let market: String?
    let offeringSettings: Settings
}

enum CloudOffering: String, Sendable {
    case gamePass = "xgpuweb"
    case freeToPlay = "xgpuwebf2p"
    var label: String { self == .gamePass ? "xCloud catalog access" : "Free-to-play access only" }
}

enum AuthError: Error, LocalizedError, Equatable {
    case service(stage: String, status: Int, code: String)
    case invalidResponse(String)
    case expired
    case declined
    case keychain(Int32)
    case network

    var errorDescription: String? {
        switch self {
        case .service(let stage, let status, let code):
            let hint: String
            switch code {
            case "invalid_grant": hint = "The saved sign-in is no longer valid. Sign in again."
            case "invalid_client", "unauthorized_client": hint = "Microsoft rejected the application's public client configuration."
            case "2148916233": hint = "Create an Xbox profile for this Microsoft account first."
            case "2148916238": hint = "This account needs family or age-related Xbox setup."
            case "2148916235": hint = "Xbox Live is not available for this account's region."
            default: hint = status == 403 ? "Check your account eligibility and supported region." : "Try again; the service may be unavailable."
            }
            return "\(stage) failed (HTTP \(status)). \(hint)"
        case .invalidResponse(let stage): return "\(stage) returned an unsupported response. Please try again."
        case .expired: return "The sign-in code expired. Start sign-in again."
        case .declined: return "Microsoft sign-in was declined."
        case .keychain(let status): return "Keychain access failed (\(status)). Check macOS Keychain access and try again."
        case .network: return "Cannot reach the authentication service. Check your connection and try again."
        }
    }
}

// API redirects are unexpected. Never forward a credential-bearing POST to a
// redirected destination. Browser sign-in is separate from this API session.
final class AuthRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct XboxAuthService: Sendable {
    // Public client identifier used by XStreaming's current MSAL implementation.
    // This is not an XFrame-owned registration and contains no client secret.
    static let clientID = "1f907974-e22b-4810-a9de-d9647380c97e"
    static let scope = "xboxlive.signin openid profile offline_access"
    private static let authority = "https://login.microsoftonline.com/consumers/oauth2/v2.0/"
    private let session: URLSession
    private let sleep: @Sendable (Int) async throws -> Void

    init(session: URLSession? = nil,
         sleep: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: configuration, delegate: AuthRedirectPolicy(), delegateQueue: nil)
        }
        self.sleep = sleep
    }

    func requestDeviceCode() async throws -> DeviceAuthorization {
        let value: DeviceAuthorization = try await form("devicecode", fields: ["client_id": Self.clientID, "scope": Self.scope], stage: "Microsoft sign-in")
        guard !value.device_code.isEmpty, !value.user_code.isEmpty, value.expires_in > 0,
              Self.isVerificationURL(value.verification_uri) else { throw AuthError.invalidResponse("Microsoft sign-in") }
        return value
    }

    static func isVerificationURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.port == nil &&
        ["microsoft.com", "www.microsoft.com", "login.microsoftonline.com", "login.live.com"].contains(url.host ?? "")
    }

    func poll(_ authorization: DeviceAuthorization) async throws -> MicrosoftToken {
        var interval = authorization.pollingInterval
        let deadline = ContinuousClock.now.advanced(by: .seconds(authorization.expires_in))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            try await sleep(interval)
            guard ContinuousClock.now < deadline else { throw AuthError.expired }
            do {
                let token: MicrosoftToken = try await form("token", fields: [
                    "client_id": Self.clientID, "device_code": authorization.device_code,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
                ], stage: "Microsoft authorization")
                return try validate(token)
            } catch AuthError.service(_, let status, let code) {
                if status == 400 && code == "authorization_pending" { continue }
                if status == 400 && code == "slow_down" { interval += 5; continue }
                if code == "expired_token" { throw AuthError.expired }
                if code == "authorization_declined" || code == "access_denied" { throw AuthError.declined }
                throw AuthError.service(stage: "Microsoft authorization", status: status, code: code)
            }
        }
        throw AuthError.expired
    }

    func refresh(_ token: String) async throws -> MicrosoftToken {
        let value: MicrosoftToken = try await form("token", fields: [
            "client_id": Self.clientID, "grant_type": "refresh_token", "refresh_token": token, "scope": Self.scope
        ], stage: "Restoring Microsoft sign-in")
        return try validate(value)
    }

    func consoleTransferToken(refreshToken: String) async throws -> ConsoleTransferToken {
        var request = URLRequest(url: URL(string: "https://login.live.com/oauth20_token.srf")!)
        request.httpBody = Self.formBody([
            "client_id": Self.clientID, "grant_type": "refresh_token", "refresh_token": refreshToken,
            "scope": "service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN"
        ])
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let token: ConsoleTransferToken = try await send(request, stage: "Cloud console authorization")
        guard !token.access_token.isEmpty else { throw AuthError.invalidResponse("Cloud console authorization") }
        return token
    }

    func xboxUserToken(accessToken: String) async throws -> XboxToken {
        try await json("https://user.auth.xboxlive.com/user/authenticate", body: [
            "Properties": ["AuthMethod": "RPS", "RpsTicket": "d=" + accessToken, "SiteName": "user.auth.xboxlive.com"],
            "RelyingParty": "http://auth.xboxlive.com", "TokenType": "JWT"
        ], stage: "Xbox authentication")
    }

    func xsts(userToken: String, relyingParty: String) async throws -> XboxToken {
        try await json("https://xsts.auth.xboxlive.com/xsts/authorize", body: [
            "Properties": ["SandboxId": "RETAIL", "UserTokens": [userToken]],
            "RelyingParty": relyingParty, "TokenType": "JWT"
        ], stage: "Xbox authorization")
    }

    func cloud(token: String, offering: CloudOffering) async throws -> CloudToken {
        let result: CloudToken = try await json(
            "https://\(offering.rawValue).gssv-play-prod.xboxlive.com/v2/login/user",
            body: ["token": token, "offeringId": offering.rawValue], stage: "xCloud access",
            headers: ["x-gssv-client": "XboxComBrowser"])
        guard !result.gsToken.isEmpty, result.durationInSeconds > 0,
              !result.offeringSettings.regions.isEmpty,
              result.offeringSettings.regions.allSatisfy({
                  $0.baseUri.scheme == "https" && $0.baseUri.user == nil && $0.baseUri.password == nil &&
                  $0.baseUri.port == nil && ($0.baseUri.host ?? "").hasSuffix(".xboxlive.com")
              }) else { throw AuthError.invalidResponse("xCloud access") }
        return result
    }

    private func validate(_ token: MicrosoftToken) throws -> MicrosoftToken {
        guard !token.access_token.isEmpty, token.expires_in > 0 else { throw AuthError.invalidResponse("Microsoft authorization") }
        return token
    }

    static func formBody(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(fields.sorted { $0.key < $1.key }.map {
            $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" +
            $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&").utf8)
    }

    private func form<T: Decodable>(_ path: String, fields: [String: String], stage: String) async throws -> T {
        var request = URLRequest(url: URL(string: Self.authority + path)!)
        request.httpBody = Self.formBody(fields)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return try await send(request, stage: stage)
    }

    private func json<T: Decodable>(_ endpoint: String, body: [String: Any], stage: String,
                                     headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "x-xbl-contract-version")
        request.setValue("https://www.xbox.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.xbox.com/", forHTTPHeaderField: "Referer")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await send(request, stage: stage)
    }

    private func send<T: Decodable>(_ original: URLRequest, stage: String) async throws -> T {
        try Task.checkCancellation()
        var request = original
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            try Task.checkCancellation()
            throw AuthError.network
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse(stage) }
        guard (200..<300).contains(http.statusCode) else {
            // Never pass service messages, request bodies, or token-bearing URLs
            // into UI errors or logs. Only allow known protocol codes.
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let known = ["authorization_pending", "slow_down", "authorization_declined", "access_denied",
                         "expired_token", "invalid_grant", "invalid_client", "unauthorized_client", "bad_verification_code"]
            let raw = object?["error"] as? String ?? ""
            let xerr = (object?["XErr"] as? NSNumber)?.stringValue
            let code = known.contains(raw) ? raw : (["2148916233", "2148916238", "2148916235"].contains(xerr ?? "") ? xerr! : "unknown")
            throw AuthError.service(stage: stage, status: http.statusCode, code: code)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AuthError.invalidResponse(stage) }
    }
}

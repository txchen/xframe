import Foundation
import Testing
@testable import XFrame

private struct Reply: Sendable {
    let status: Int
    let json: String
    init(_ status: Int, _ json: String) { self.status = status; self.json = json }
    init(_ json: String) { self.init(200, json) }
}

private final class AuthScript: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var paths: [String] = []
    private var intervals: [Int] = []
    private var launches: [(Data, String?)] = []
    var launchRequests: [(Data, String?)] { lock.withLock { launches } }
    init(_ replies: [Reply]) { self.replies = replies }
    func reply(for request: URLRequest) -> Reply {
        lock.withLock {
            paths.append(request.url!.absoluteString)
            if request.url?.path == "/v5/sessions/cloud/play" || request.url?.path == "/v5/sessions/home/play" {
                var body = request.httpBody ?? Data()
                if body.isEmpty, let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while true {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        body.append(contentsOf: buffer.prefix(count))
                    }
                }
                launches.append((body, request.value(forHTTPHeaderField: "X-MS-Device-Info")))
            }
            if request.url?.host == "catalog.gamepass.com" {
                guard request.value(forHTTPHeaderField: "ms-cv") != nil,
                      request.value(forHTTPHeaderField: "calling-app-name") != nil,
                      request.value(forHTTPHeaderField: "calling-app-version") != nil,
                      request.value(forHTTPHeaderField: "Authorization") == nil else { return Reply(400, "{}") }
            }
            return replies.isEmpty ? Reply(500, "{}") : replies.removeFirst()
        }
    }
    func recordSleep(_ interval: Int) { lock.withLock { intervals.append(interval) } }
    var sleeps: [Int] { lock.withLock { intervals } }
    var requests: [String] { lock.withLock { paths } }
}

private final class AuthRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var scripts: [String: AuthScript] = [:]
    func set(_ script: AuthScript, id: String) { lock.withLock { scripts[id] = script } }
    func get(_ id: String) -> AuthScript? { lock.withLock { scripts[id] } }
    func remove(_ id: String) { _ = lock.withLock { scripts.removeValue(forKey: id) } }
}

private final class StubAuthProtocol: URLProtocol, @unchecked Sendable {
    static let router = AuthRouter()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Test-ID") ?? ""
        guard let script = Self.router.get(id) else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        let reply = script.reply(for: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class AuthHarness {
    let script: AuthScript
    let service: XboxAuthService
    private let id = UUID().uuidString
    let session: URLSession
    init(_ replies: [Reply], waitForCancellation: Bool = false) {
        let script = AuthScript(replies)
        self.script = script
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubAuthProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Test-ID": id]
        let session = URLSession(configuration: configuration)
        self.session = session
        service = XboxAuthService(session: session, sleep: { seconds in
            script.recordSleep(seconds)
            if waitForCancellation { try await Task.sleep(for: .seconds(600)) }
        })
        StubAuthProtocol.router.set(script, id: id)
    }
    deinit { session.invalidateAndCancel(); StubAuthProtocol.router.remove(id) }
}

private let deviceJSON = #"{"device_code":"test-device","user_code":"TEST-CODE","verification_uri":"https://microsoft.com/link","expires_in":900,"interval":5}"#
private let tokenJSON = #"{"access_token":"test-access","refresh_token":"rotated-refresh","expires_in":3600}"#
private let xboxJSON = #"{"Token":"test-xbox","DisplayClaims":{"xui":[{"gtg":"Test Player","uhs":"test-hash"}]}}"#
private let cloudJSON = #"{"gsToken":"test-cloud","durationInSeconds":14400,"market":"US","offeringSettings":{"regions":[{"name":"Test Region","baseUri":"https://test.gssv-play-prod.xboxlive.com/","isDefault":true}]}}"#

@Test func devicePollingRespectsPendingAndSlowDown() async throws {
    let harness = AuthHarness([Reply(deviceJSON), Reply(400, #"{"error":"authorization_pending"}"#),
        Reply(400, #"{"error":"slow_down"}"#), Reply(400, #"{"error":"authorization_pending"}"#), Reply(tokenJSON)])
    let code = try await harness.service.requestDeviceCode()
    let token = try await harness.service.poll(code)
    #expect(token.refresh_token == "rotated-refresh")
    #expect(harness.script.sleeps == [5, 5, 10, 10])
}

@Test func untrustedVerificationURLIsRejected() async {
    let harness = AuthHarness([Reply(deviceJSON.replacingOccurrences(of: "https://microsoft.com/link", with: "https://microsoft.com.evil.invalid/link"))])
    do { _ = try await harness.service.requestDeviceCode(); Issue.record("Untrusted login URL was accepted") }
    catch { #expect(error as? AuthError == .invalidResponse("Microsoft sign-in")) }
}

@Test func authorizationDeclineStopsPolling() async throws {
    let harness = AuthHarness([Reply(deviceJSON), Reply(400, #"{"error":"authorization_declined"}"#)])
    let code = try await harness.service.requestDeviceCode()
    do { _ = try await harness.service.poll(code); Issue.record("Declined authorization succeeded") }
    catch { #expect(error as? AuthError == .declined) }
    #expect(harness.script.requests.count == 2)
}

@Test func errorsDoNotEchoCredentials() async {
    let canary = "SECRET-MUST-NOT-APPEAR"
    let harness = AuthHarness([Reply(400, "{\"error\":\"\(canary)\",\"error_description\":\"\(canary)\"}")])
    do { _ = try await harness.service.refresh(canary); Issue.record("Bad response succeeded") }
    catch {
        #expect(!error.localizedDescription.contains(canary))
        #expect(error as? AuthError == .service(stage: "Restoring Microsoft sign-in", status: 400, code: "unknown"))
    }
}

@Test func formEncodingPreservesTokenCharacters() {
    let body = String(decoding: XboxAuthService.formBody(["refresh_token": "a+b&c=d% e"]), as: UTF8.self)
    #expect(body == "refresh_token=a%2Bb%26c%3Dd%25%20e")
}

@Test func catalogRequiresHeadersWithoutLeakingBearerToken() async throws {
    let harness = AuthHarness([
        Reply(#"{"results":[{"titleId":"TEST","details":{"productId":"PRODUCT"}}]}"#),
        Reply(#"{"Products":{"PRODUCT":{"ProductTitle":"Test Game"}}}"#)
    ])
    let credential = try JSONDecoder().decode(CloudToken.self, from: Data(cloudJSON.utf8))
    let service = try CloudService(credential: credential, expires: Date().addingTimeInterval(3600), session: harness.session)
    let games = try await service.games()
    #expect(games == [CloudGame(id: "TEST", name: "Test Game", productID: "PRODUCT")])
}

@Test func catalogPreservesAccountEntitlementEvidence() async throws {
    let harness = AuthHarness([
        Reply(#"{"results":[{"titleId":"PASS","details":{"hasEntitlement":true,"programs":["GPULTIMATE"],"isFreeInStore":false}},{"titleId":"007","details":{"hasEntitlement":false}},{"titleId":"UNKNOWN"}]}"#)
    ])
    let credential = try JSONDecoder().decode(CloudToken.self, from: Data(cloudJSON.utf8))
    let service = try CloudService(credential: credential, expires: Date().addingTimeInterval(3600), session: harness.session)
    let games = try await service.games()
    #expect(games.first { $0.id == "PASS" }?.access == CloudGameAccess(entitled: true, programs: ["GPULTIMATE"]))
    #expect(games.first { $0.id == "007" }?.access.entitled == false)
    #expect(games.first { $0.id == "UNKNOWN" }?.access.entitled == nil)
}

@Test func cloudHTTPFlowSupportsAcceptedCreationConnectAndEmptyDeletion() async throws {
    let harness = AuthHarness([
        Reply(202, #"{"sessionPath":"/v5/sessions/cloud/test-session"}"#),
        Reply(#"{"state":"ReadyToConnect"}"#), Reply(204, ""),
        Reply(#"{"state":"Provisioned"}"#), Reply(#"{"keepAlivePulseInSeconds":20}"#), Reply(204, "")
    ])
    let credential = try JSONDecoder().decode(CloudToken.self, from: Data(cloudJSON.utf8))
    let service = try CloudService(credential: credential, expires: Date().addingTimeInterval(3600),
        session: harness.session, transferToken: { "test-transfer-token" })
    let url = try await service.create(title: "TEST")
    #expect(try await service.state(at: url).state == "ReadyToConnect")
    try await service.connect(at: url)
    #expect(try await service.state(at: url).state == "Provisioned")
    try await service.configuration(at: url)
    try await service.end(at: url)
    #expect(harness.script.requests.map { URL(string: $0)!.lastPathComponent } ==
            ["play", "state", "connect", "state", "configuration", "test-session"])
}

@Test func homeServiceListsWakesCreatesAndDeletesWithoutPowerOff() async throws {
    let harness = AuthHarness([
        Reply(#"{"result":[{"id":"live-id","name":"Series X","model":"XboxSeriesX"},{"id":"elsewhere","name":"Other Xbox"}]}"#),
        Reply(#"{"results":[{"serverId":"live-id","deviceName":"Series X","powerState":"On"}]}"#),
        Reply(#"{"result":{}}"#),
        Reply(202, #"{"sessionPath":"/v5/sessions/home/test-session"}"#),
        Reply(204, "")
    ])
    let credential = try JSONDecoder().decode(CloudToken.self, from: Data(cloudJSON.utf8))
    let home = try HomeService(credential: credential, expires: Date().addingTimeInterval(3600),
                               webToken: "web-token", userHash: "hash", session: harness.session)
    let consoles: [HomeConsole]
    do { consoles = try await home.consoles() }
    catch { Issue.record("Console list: \(error); requests: \(harness.script.requests)"); return }
    #expect(consoles.count == 2)
    #expect(consoles.first { $0.id == "live-id" }?.inHomeService == true)
    #expect(consoles.first { $0.id == "elsewhere" }?.inHomeService == false)
    do { try await home.wake("live-id") }
    catch { Issue.record("Wake: \(error); requests: \(harness.script.requests)"); return }
    #expect(!harness.script.requests.contains { $0.contains("/sessions/home/play") })
    let handle: URL
    do { handle = try await home.create(title: "live-id", preferences: .init()) }
    catch { Issue.record("Create: \(error); requests: \(harness.script.requests)"); return }
    #expect(handle.path == "/v5/sessions/home/test-session")
    try await home.end(at: handle)
    let body = try #require(harness.script.launchRequests.first?.0)
    let launch = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(launch["serverId"] as? String == "live-id")
    #expect(launch["titleId"] as? String == "")
    #expect(harness.script.requests.contains { $0.contains("/commands") })
    #expect(!harness.script.requests.contains { $0.contains("TurnOff") })
    #expect(harness.script.requests.last?.contains("/v5/sessions/home/test-session") == true)
}

@Test func associatedConsolesRemainVisibleWhenHomeListFails() async throws {
    let harness = AuthHarness([
        Reply(#"{"result":[{"id":"living-room","name":"Living Room","powerState":"On"}]}"#),
        Reply(503, "{}")
    ])
    let credential = try JSONDecoder().decode(CloudToken.self, from: Data(cloudJSON.utf8))
    let home = try HomeService(credential: credential, expires: Date().addingTimeInterval(3600),
                               webToken: "web-token", userHash: "hash", session: harness.session)
    let console = try #require(await home.consoles().first)
    #expect(console.id == "living-room")
    #expect(!console.homeServiceChecked)
    #expect(!console.inHomeService)
    #expect(!console.local)
}

@Test func associatedConsolesCanBeListedWithoutHomeAuthorization() async throws {
    let harness = AuthHarness([Reply(#"{"result":[{"id":"living-room","name":"Living Room"}]}"#)])
    let home = try HomeService(credential: nil, expires: .distantPast,
                               webToken: "web-token", userHash: "hash", session: harness.session)
    let consoles = try await home.consoles()
    #expect(consoles.count == 1)
    #expect(consoles[0].id == "living-room")
    #expect(!consoles[0].homeServiceChecked)
    #expect(harness.script.requests.count == 1)
}

@Test func catalogHydratesOptionalArtworkCategoriesAndPublisher() async throws {
    let harness = AuthHarness([
        Reply(#"{"results":[{"titleId":"TEST","details":{"productId":"PRODUCT"}},{"titleId":"TEST","details":{"name":"Duplicate"}},{"titleId":"FALLBACK","details":{"name":"Fallback Game"}}]}"#),
        Reply(#"{"Products":{"PRODUCT":{"ProductTitle":"Test Game","Image_Poster":{"URL":"//store-images.s-microsoft.com/poster"},"Categories":["Action","Action",""],"PublisherName":"Publisher"}}}"#)
    ])
    let credential = try JSONDecoder().decode(CloudToken.self, from: Data(cloudJSON.utf8))
    let service = try CloudService(credential: credential, expires: Date().addingTimeInterval(3600), session: harness.session)
    let games = try await service.games()
    #expect(games.count == 2)
    let game = try #require(games.first { $0.id == "TEST" })
    #expect(game.posterURL?.absoluteString == "https://store-images.s-microsoft.com/poster")
    #expect(game.categories == ["Action"])
    #expect(game.publisher == "Publisher")
    let fallback = try #require(games.first { $0.id == "FALLBACK" })
    #expect(fallback.name == "Fallback Game" && fallback.categories.isEmpty && fallback.posterURL == nil)
}

@Test func consoleTransferTokenUsesMicrosoftEndpoint() async throws {
    let harness = AuthHarness([Reply(#"{"access_token":"test-transfer","refresh_token":"test-rotation"}"#)])
    let token = try await harness.service.consoleTransferToken(refreshToken: "test-refresh")
    #expect(token.access_token == "test-transfer")
    #expect(token.refresh_token == "test-rotation")
    #expect(harness.script.requests == ["https://login.live.com/oauth20_token.srf"])
}

@Test func streamingSignalingExchangesEnvelopesAndKeepalive() async throws {
    let sdpEnvelope = #"{"exchangeResponse":"{\"sdp\":\"v=0\\r\\n\"}"}"#
    let iceEnvelope = #"{"exchangeResponse":"[{\"candidate\":\"candidate:test\",\"sdpMid\":\"0\",\"sdpMLineIndex\":\"0\"}]"}"#
    let harness = AuthHarness([Reply(202, ""), Reply(sdpEnvelope), Reply(202, ""), Reply(iceEnvelope),
                               Reply(#"{"keepAlivePulseInSeconds":20}"#), Reply(204, "")])
    let credential = try JSONDecoder().decode(CloudToken.self, from: Data(cloudJSON.utf8))
    let service = try CloudService(credential: credential, expires: Date().addingTimeInterval(3600), session: harness.session)
    let url = URL(string: "https://test.gssv-play-prod.xboxlive.com/v5/sessions/cloud/test-session")!
    #expect(try await service.exchangeSDP(at: url, offer: "v=0\r\n") == "v=0\r\n")
    let candidates = try await service.exchangeICE(at: url, candidates: [.init(candidate: "candidate:local", sdpMid: "0", sdpMLineIndex: 0)])
    #expect(candidates.count == 1)
    #expect(candidates.first?.sdpMLineIndex == 0)
    #expect(try await service.keepAliveInterval(at: url) == 20)
    try await service.keepAlive(at: url)
}

@Test(arguments: [204, 404, 410]) func cleanupStillAttemptsDeletionAfterCredentialExpiry(status: Int) async throws {
    let harness = AuthHarness([Reply(status, "")])
    let credential = try JSONDecoder().decode(CloudToken.self, from: Data(cloudJSON.utf8))
    let service = try CloudService(credential: credential, expires: Date().addingTimeInterval(-1), session: harness.session)
    let url = URL(string: "https://test.gssv-play-prod.xboxlive.com/v5/sessions/cloud/test-session")!
    try await service.end(at: url)
    #expect(harness.script.requests == [url.absoluteString])
}

@MainActor
private final class MemoryCredentials: CredentialStore {
    var token: String?
    init(_ token: String? = nil) { self.token = token }
    func load() throws -> String? { token }
    func save(_ refreshToken: String) throws { token = refreshToken }
    func delete() throws { token = nil }
}

@MainActor
private func waitForIdle(_ account: XboxAccount) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while account.isBusy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    #expect(!account.isBusy)
}

@Test @MainActor func restoreRotatesTokenAndDistinguishesFreeToPlay() async throws {
    let harness = AuthHarness([Reply(tokenJSON), Reply(xboxJSON), Reply(xboxJSON), Reply(xboxJSON), Reply(cloudJSON), Reply(403, "{}"), Reply(cloudJSON)])
    let store = MemoryCredentials("previous-refresh")
    let account = XboxAccount(service: harness.service, store: store)
    #expect(!account.hasCloudAccess)
    account.restore()
    #expect(!account.hasCloudAccess)
    try await waitForIdle(account)
    #expect(store.token == "rotated-refresh")
    #expect(account.gamertag == "Test Player")
    #expect(account.offering == .freeToPlay)
    #expect(account.hasCloudAccess)
    #expect(account.hasConsoleAccess)
    #expect(account.regionNames == ["Test Region"])
    #expect(account.accessExpires != nil)
    #expect(account.errorMessage == nil)
    #expect(harness.script.requests.last?.contains("xgpuwebf2p") == true)
    account.signOut()
    #expect(store.token == nil)
    #expect(account.accessExpires == nil)
    #expect(account.gamertag == nil)
    #expect(!account.hasCloudAccess)
}

@Test @MainActor func downstreamFailurePreservesRotatedRefreshToken() async throws {
    let harness = AuthHarness([Reply(tokenJSON), Reply(503, "{}")])
    let store = MemoryCredentials("previous-refresh")
    let account = XboxAccount(service: harness.service, store: store)
    account.restore()
    try await waitForIdle(account)
    #expect(store.token == "rotated-refresh")
    #expect(account.hasSavedSignIn)
    #expect(!account.hasCloudAccess)
    #expect(account.errorMessage != nil)
    #expect(account.accessExpires == nil)
}

@Test @MainActor func consoleAccessSurvivesCloudDenial() async throws {
    let harness = AuthHarness([Reply(tokenJSON), Reply(xboxJSON), Reply(xboxJSON), Reply(xboxJSON),
                               Reply(cloudJSON), Reply(403, "{}"), Reply(403, "{}")])
    let account = XboxAccount(service: harness.service, store: MemoryCredentials("saved"))
    account.restore()
    try await waitForIdle(account)
    #expect(account.hasXboxSignIn)
    #expect(account.hasConsoleAccess)
    #expect(!account.hasCloudAccess)
    #expect(account.homeError == nil)
    #expect(account.cloudError != nil)
    #expect(try account.homeService().stream?.source == .home)
}

@Test @MainActor func signOutCancelsPendingAuthorization() async throws {
    let harness = AuthHarness([Reply(deviceJSON)], waitForCancellation: true)
    let store = MemoryCredentials()
    let account = XboxAccount(service: harness.service, store: store)
    account.signIn()
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while account.userCode == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    #expect(account.userCode == "TEST-CODE")
    account.signOut()
    try await Task.sleep(for: .milliseconds(20))
    #expect(!account.isBusy)
    #expect(account.userCode == nil)
    #expect(store.token == nil)
    #expect(account.status == "Signed out of XFrame")
}

@Test func cloudLaunchSendsSelectedLanguageAndConsistentQualityProfile() async throws {
    for preferences in [CloudStreamPreferences(),
                        CloudStreamPreferences(quality: .hq, language: .simplifiedChinese),
                        CloudStreamPreferences(quality: .hq, language: .traditionalChinese)] {
        let harness = AuthHarness([Reply(202, #"{"sessionPath":"/v5/sessions/cloud/test-session"}"#)])
        let credential = try JSONDecoder().decode(CloudToken.self, from: Data(cloudJSON.utf8))
        let service = try CloudService(credential: credential, expires: Date().addingTimeInterval(3600), session: harness.session)
        _ = try await service.create(title: "TEST", preferences: preferences)
        let captured = try #require(harness.script.launchRequests.first)
        let body = try #require(JSONSerialization.jsonObject(with: captured.0) as? [String: Any])
        let settings = try #require(body["settings"] as? [String: Any])
        let header = try #require(captured.1)
        let device = try #require(JSONSerialization.jsonObject(with: Data(header.utf8)) as? [String: Any])
        let dev = try #require(device["dev"] as? [String: Any])
        let os = try #require(dev["os"] as? [String: Any])
        let display = try #require(dev["displayInfo"] as? [String: Any])
        let dimensions = try #require(display["dimensions"] as? [String: Int])
        let hq = preferences.quality == .hq
        #expect(body["titleId"] as? String == "TEST")
        #expect(settings["locale"] as? String == preferences.language.rawValue)
        #expect(settings["osName"] as? String == (hq ? "tizen" : "macos"))
        #expect(os["name"] as? String == (hq ? "tizen" : "macos"))
        #expect(os["ver"] as? String == (hq ? "22631.2715" : "27"))
        let hardware = try #require(dev["hw"] as? [String: String])
        #expect(hardware["make"] == (hq ? "Microsoft" : "Apple"))
        if hq {
            let browser = try #require(dev["browser"] as? [String: String])
            #expect(browser["browserName"] == "edge" && browser["browserVersion"] == "140.0.3485.66")
        } else { #expect(dev["browser"] == nil) }
        #expect(dimensions["widthInPixels"] == (hq ? 4096 : 1920))
        #expect(dimensions["heightInPixels"] == (hq ? 2160 : 1080))
    }
}

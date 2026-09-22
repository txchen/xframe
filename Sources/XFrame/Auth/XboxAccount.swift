import Foundation
import Observation

@Observable
@MainActor
final class XboxAccount {
    var showingAccount = false
    var hasCloudAccess: Bool { offering != nil }
    private(set) var status = "Not signed in"
    private(set) var errorMessage: String?
    private(set) var gamertag: String?
    private(set) var userCode: String?
    private(set) var verificationURL: URL?
    private(set) var codeExpires: Date?
    private(set) var accessExpires: Date?
    private(set) var offering: CloudOffering?
    private(set) var regionNames: [String] = []
    private(set) var selectedRegion = ""
    private(set) var defaultRegion: String?
    var requestedRegion: String? { selectedRegion.isEmpty ? defaultRegion : selectedRegion }

    func selectRegion(_ name: String) {
        guard !isBusy && !library.loading && !library.ownsSession,
              name.isEmpty || regionNames.contains(name), name != selectedRegion else { return }
        selectedRegion = name
        library.reset()
    }
    private(set) var hasSavedSignIn = false
    private(set) var isBusy = false
    let library = CloudLibrary()

    func cloudService() throws -> CloudService {
        guard let cloudCredential, let accessExpires, accessExpires > Date(), !isBusy else { throw CloudError.expired }
        return try CloudService(credential: cloudCredential, expires: accessExpires,
                                regionName: selectedRegion.isEmpty ? nil : selectedRegion, transferToken: { [weak self] in
            guard let self else { throw CloudError.expired }
            return try await self.consoleTransferToken()
        })
    }

    private func consoleTransferToken() async throws -> String {
        guard let saved = try store.load() else { throw CloudError.expired }
        let token = try await service.consoleTransferToken(refreshToken: saved)
        if let rotated = token.refresh_token, !rotated.isEmpty { try store.save(rotated) }
        return token.access_token
    }
    // Tokens never enter observable view state or diagnostics.
    @ObservationIgnored private var cloudCredential: CloudToken?
    @ObservationIgnored private let service: XboxAuthService
    @ObservationIgnored private let store: any CredentialStore
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(service: XboxAuthService = XboxAuthService(), store: any CredentialStore = FileCredentialStore()) {
        self.service = service
        self.store = store
    }

    func signIn() {
        guard !isBusy && !library.ownsSession && !library.loading else { return }
        begin(status: "Requesting a Microsoft sign-in code…")
        let run = generation
        task = Task {
            do {
                let authorization = try await service.requestDeviceCode()
                try check(run)
                userCode = authorization.user_code
                verificationURL = authorization.verification_uri
                codeExpires = Date().addingTimeInterval(Double(authorization.expires_in))
                status = "Complete sign-in on Microsoft's website"
                let token = try await service.poll(authorization)
                try check(run)
                clearDeviceCode()
                try save(token, fallback: nil)
                try await verifyCloud(token.access_token, run: run)
                finish(run)
            } catch { failed(error, run: run) }
        }
    }

    func restore() {
        guard !isBusy && !library.ownsSession && !library.loading else { return }
        do {
            guard let saved = try store.load() else { hasSavedSignIn = false; return }
            hasSavedSignIn = true
            begin(status: "Restoring Microsoft sign-in…")
            let run = generation
            task = Task {
                do {
                    let token = try await service.refresh(saved)
                    try check(run)
                    // Persist refresh-token rotation before later Xbox calls can fail.
                    try save(token, fallback: saved)
                    try await verifyCloud(token.access_token, run: run)
                    finish(run)
                } catch { failed(error, run: run) }
            }
        } catch {
            errorMessage = (error as? AuthError)?.localizedDescription ?? "Cannot read saved sign-in."
            status = "Saved sign-in unavailable"
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isBusy = false
        clearDeviceCode()
        status = hasSavedSignIn ? "Sign-in saved; access check canceled" : "Sign-in canceled"
    }

    func signOut() {
        guard !library.ownsSession && !library.loading else { return }
        cancel()
        clearAccess()
        gamertag = nil
        errorMessage = nil
        do {
            try store.delete()
            hasSavedSignIn = false
            status = "Signed out of XFrame"
        } catch {
            status = "Could not remove saved sign-in"
            errorMessage = (error as? AuthError)?.localizedDescription ?? "Local sign-in file removal failed."
        }
    }

    private func begin(status: String) {
        generation += 1
        isBusy = true
        errorMessage = nil
        self.status = status
        clearDeviceCode()
        clearAccess()
        gamertag = nil
    }

    private func check(_ run: Int) throws {
        try Task.checkCancellation()
        if run != generation { throw CancellationError() }
    }

    private func save(_ token: MicrosoftToken, fallback: String?) throws {
        guard let refresh = token.refresh_token ?? fallback, !refresh.isEmpty else {
            throw AuthError.invalidResponse("Persistent Microsoft sign-in")
        }
        try store.save(refresh)
        hasSavedSignIn = true
    }

    private func verifyCloud(_ accessToken: String, run: Int) async throws {
        status = "Authenticating with Xbox…"
        let user = try await service.xboxUserToken(accessToken: accessToken)
        try check(run)
        guard !user.Token.isEmpty else { throw AuthError.invalidResponse("Xbox authentication") }
        status = "Reading Xbox profile…"
        let profile = try await service.xsts(userToken: user.Token, relyingParty: "http://xboxlive.com")
        try check(run)
        gamertag = profile.gamertag ?? "Xbox account"
        status = "Requesting xCloud authorization…"
        let streaming = try await service.xsts(userToken: user.Token, relyingParty: "http://gssv.xboxlive.com/")
        try check(run)
        guard !streaming.Token.isEmpty else { throw AuthError.invalidResponse("xCloud authorization") }
        status = "Checking xCloud access…"
        var selected = CloudOffering.gamePass
        let cloud: CloudToken
        do { cloud = try await service.cloud(token: streaming.Token, offering: selected) }
        catch AuthError.service(_, let statusCode, _) where statusCode == 403 {
            try check(run)
            selected = .freeToPlay
            status = "Checking free-to-play xCloud access…"
            cloud = try await service.cloud(token: streaming.Token, offering: selected)
        }
        try check(run)
        cloudCredential = cloud
        offering = selected
        regionNames = cloud.offeringSettings.regions.map(\.name)
        defaultRegion = (cloud.offeringSettings.regions.first(where: { $0.isDefault == true })
            ?? cloud.offeringSettings.regions.first)?.name
        if !regionNames.contains(selectedRegion) { selectedRegion = "" }
        accessExpires = Date().addingTimeInterval(Double(cloud.durationInSeconds))
        status = "xCloud credentials verified"
    }

    private func finish(_ run: Int) {
        guard run == generation else { return }
        isBusy = false
        task = nil
    }

    private func failed(_ error: Error, run: Int) {
        guard run == generation else { return }
        clearDeviceCode()
        clearAccess()
        if error is CancellationError { status = "Canceled" }
        else {
            status = hasSavedSignIn ? "Sign-in saved; xCloud access not verified" : "Sign-in failed"
            errorMessage = (error as? AuthError)?.localizedDescription ?? "Authentication failed. Please try again."
        }
        finish(run)
    }

    private func clearDeviceCode() { userCode = nil; verificationURL = nil; codeExpires = nil }
    private func clearAccess() {
        cloudCredential = nil; accessExpires = nil; offering = nil; regionNames = []
        defaultRegion = nil
        library.reset()
    }
}

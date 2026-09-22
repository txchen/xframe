import Foundation
import Observation

@Observable @MainActor
final class CloudLibrary {
    var search = ""
    var selection: String?
    var viewError: String?
    private(set) var games: [CloudGame] = []
    private(set) var status = "Load games after signing in."
    private(set) var errorMessage: String?
    private(set) var loading = false
    private(set) var ownsSession = false
    private(set) var ending = false
    private(set) var ready = false
    private(set) var activeGame: String?
    @ObservationIgnored private var service: (any CloudServing)?
    @ObservationIgnored private var handle: URL?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cancelRequested = false
    @ObservationIgnored private let sleep: @Sendable () async throws -> Void

    init(sleep: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }) {
        self.sleep = sleep
    }

    func reset() {
        guard !ownsSession && !loading else { return }
        games = []
        selection = nil
        service = nil
        errorMessage = nil
        viewError = nil
        status = "Load games after signing in."
    }

    func load(using service: any CloudServing) {
        guard !ownsSession && !loading else { return }
        self.service = service
        loading = true
        games = []
        errorMessage = nil
        status = "Loading cloud games…"
        task = Task {
            defer { loading = false; task = nil }
            do { games = try await service.games(); status = "\(games.count) cloud games" }
            catch { fail(error) }
        }
    }

    func start(_ game: CloudGame) {
        guard !ownsSession && !loading, games.contains(game), let service else { return }
        ownsSession = true
        cancelRequested = false
        ready = false
        errorMessage = nil
        activeGame = game.name
        status = "Starting \(game.name)…"
        task = Task {
            do {
                // Do not cancel a creation POST: retain the returned handle so it can be deleted.
                handle = try await service.create(title: game.id)
                if cancelRequested { await cleanup(); return }
                let deadline = ContinuousClock.now.advanced(by: .seconds(600))
                var connected = false
                while ContinuousClock.now < deadline {
                    guard let current = handle else { throw CloudError.response }
                    let state = try await service.state(at: current)
                    if let transfer = state.transferUri {
                        guard CloudService.trusted(transfer) else { throw CloudError.response }
                        handle = try CloudService.sessionURL(current.path, relativeTo: transfer)
                    }
                    if cancelRequested { await cleanup(); return }
                    switch state.state {
                    case "WaitingForResources": status = "Queued — waiting for a cloud console…"
                    case "Provisioning": status = "Starting the cloud game…"
                    case "ReadyToConnect":
                        status = "Authorizing the cloud console…"
                        if !connected {
                            try await service.connect(at: handle!)
                            connected = true
                        }
                        if cancelRequested { await cleanup(); return }
                    case "Provisioned":
                        try await service.configuration(at: handle!)
                        if cancelRequested { await cleanup(); return }
                        ready = true
                        status = "Session ready — video connection is not implemented yet."
                        // A session-only test must not hold a cloud console indefinitely.
                        try await Task.sleep(for: .seconds(60))
                        status = "Ending the idle test session…"
                        await cleanup()
                        return
                    case "Failed": throw CloudError.failed
                    default: throw CloudError.unsupportedState
                    }
                    try await sleep()
                }
                throw CloudError.timeout
            } catch {
                if !cancelRequested { fail(error) }
                if handle != nil { await cleanup() }
                else {
                    // A failed POST can have reached the service. Do not claim confirmed cleanup.
                    ownsSession = false
                    status = "Start failed; no session address was received. Server allocation could not be confirmed."
                    task = nil
                }
            }
        }
    }

    func end() {
        guard ownsSession && !ending else { return }
        cancelRequested = true
        status = "Ending session…"
        // Creation and polling complete naturally; interrupt only the ready-state idle timer.
        if ready { task?.cancel() }
        else if task == nil { task = Task { await cleanup() } }
    }

    private func cleanup() async {
        guard let service, let handle else { return }
        ending = true
        ready = false
        // Independent task: cleanup must not inherit the canceled idle timer.
        let result = await Task { () -> Bool in
            do { try await service.end(at: handle); return true }
            catch { fail(error); return false }
        }.value
        ending = false
        task = nil
        if result {
            self.handle = nil
            ownsSession = false
            activeGame = nil
            status = "Session ended"
        } else { status = "Session cleanup failed — retry End Session before quitting." }
    }

    private func fail(_ error: Error) {
        errorMessage = (error as? CloudError)?.localizedDescription ?? (error as? AuthError)?.localizedDescription ?? "The cloud operation failed. Please try again."
        status = "Cloud operation failed"
    }
}

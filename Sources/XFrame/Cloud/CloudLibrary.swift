import Foundation
import Observation

@Observable @MainActor
final class CloudLibrary {
    var query = GameLibraryQuery() { didSet { if oldValue != query { rebuildPage() } } }
    var search: String {
        get { query.search }
        set { updateQuery { $0.search = newValue } }
    }
    private(set) var favorites: Set<String> { didSet { rebuildPage() } }
    private(set) var catalogLoaded = false
    private(set) var artworkRevisions: [String: Int] = [:]
    func reloadArtwork(for game: CloudGame) {
        guard games.contains(game) else { return }
        artworkRevisions[game.id, default: 0] &+= 1
    }
    @ObservationIgnored private let favoritesStore: GameFavoritesStore
    private(set) var page = GameLibraryQuery().page(in: [], favorites: [])
    private(set) var categories: [String] = []
    @ObservationIgnored private(set) var pageComputations = 0
    private func rebuildPage() {
        page = query.page(in: games, favorites: favorites)
        pageComputations += 1
    }
    var selectedGame: CloudGame? { page.games.first { $0.id == selection } }

    func updateQuery(_ change: (inout GameLibraryQuery) -> Void) {
        change(&query)
        query.pageIndex = 0
        selection = nil
    }
    func goToPage(_ index: Int) {
        query.pageIndex = min(max(0, index), page.count - 1)
        selection = nil
    }
    func moveSelection(by offset: Int) {
        guard !page.games.isEmpty else { selection = nil; return }
        let current = page.games.firstIndex { $0.id == selection }
        let index = current.map { min(max(0, $0 + offset), page.games.count - 1) }
            ?? (offset < 0 ? page.games.count - 1 : 0)
        selection = page.games[index].id
    }
    func toggleFavorite(_ game: CloudGame) {
        guard games.contains(game) else { return }
        if !favorites.insert(game.id).inserted { favorites.remove(game.id) }
        favoritesStore.save(favorites)
        query.pageIndex = page.index
        if selectedGame == nil { selection = nil }
    }
    var showingStreamSettings = false
    var streamPreferences: CloudStreamPreferences {
        didSet { preferencesStore.save(streamPreferences) }
    }
    private(set) var activeStreamPreferences: CloudStreamPreferences?
    @ObservationIgnored private let preferencesStore: CloudStreamPreferencesStore
    var selection: String?
    var viewError: String?
    var diagnosticDocument: StreamDiagnosticDocument?
    var exportingDiagnostics = false
    private(set) var games: [CloudGame] = [] {
        didSet { categories = Array(Set(games.flatMap(\.categories))).sorted(); rebuildPage() }
    }
    private(set) var status = "Load games after signing in."
    private(set) var errorMessage: String?
    private(set) var loading = false
    private(set) var ownsSession = false
    private(set) var ending = false
    private(set) var ready = false
    private(set) var activeGame: String?
    private var activeGameID: String?
    private var retryGameID: String?
    private var sleeping = false
    var retryGame: CloudGame? {
        guard !ownsSession && !loading && !sleeping else { return nil }
        return games.first { $0.id == retryGameID && $0.access.playable }
    }
    func retry() { if let game = retryGame { start(game) } }

    func systemWillSleep() {
        sleeping = true
        guard ownsSession else { return }
        retryGameID = activeGameID
        connection?.video.connectionEvent(.systemSleep)
        end()
    }
    func systemDidWake() {
        sleeping = false
        // Retry only cleanup; never allocate a cloud console on wake.
        if ownsSession && cancelRequested && task == nil { end() }
    }
    private(set) var lastVideoDiagnostics: String?
    private(set) var lastStreamReport: StreamDiagnosticReport?
    private(set) var audioMuted = false
    private(set) var audioVolume = 1.0
    func setAudio(muted: Bool, volume: Double) {
        audioMuted = muted
        audioVolume = volume.isFinite ? min(1, max(0, volume)) : 0
        connection?.configureAudio(muted: audioMuted, volume: audioVolume)
    }
    var controllerEnabled = false {
        didSet {
            connection?.controllerEnabled = controllerEnabled
        }
    }
    var keyboardEnabled = false {
        didSet {
            connection?.keyboardEnabled = keyboardEnabled
        }
    }
    @discardableResult
    func keyboardEvent(code: UInt16, down: Bool, repeatKey: Bool, shortcut: Bool) -> Bool {
        connection?.keyboardEvent(code: code, down: down, repeatKey: repeatKey, shortcut: shortcut) ?? false
    }
    func releaseKeyboard() { connection?.releaseKeyboard() }
    var playbackFocused = false { didSet { connection?.playbackFocused = playbackFocused } }
    var controllerStatus: String { connection?.controllerStatus ?? "Controller input off" }
    @ObservationIgnored private var service: (any CloudServing)?
    @ObservationIgnored private var handle: URL?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cancelRequested = false
    @ObservationIgnored private var connection: CloudVideoConnection?
    @ObservationIgnored var cyclePerformanceOverlay: (() -> Void)?
    @ObservationIgnored var displayVideo: ((LiveVideo?) -> Void)?
    @ObservationIgnored private let sleep: @Sendable () async throws -> Void

    init(favoritesStore: GameFavoritesStore = GameFavoritesStore(defaults: .standard),
         preferencesStore: CloudStreamPreferencesStore = .init(defaults: .standard),
         sleep: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }) {
        self.preferencesStore = preferencesStore
        streamPreferences = preferencesStore.load()
        self.favoritesStore = favoritesStore
        favorites = favoritesStore.load()
        self.sleep = sleep
    }

    func reset() {
        guard !ownsSession && !loading else { return }
        retryGameID = nil
        games = []
        artworkRevisions = [:]
        catalogLoaded = false
        query = GameLibraryQuery()
        selection = nil
        service = nil
        errorMessage = nil
        viewError = nil
        lastVideoDiagnostics = nil
        lastStreamReport = nil
        status = "Load games after signing in."
    }

    func load(using service: any CloudServing) {
        guard !ownsSession && !loading else { return }
        self.service = service
        loading = true
        retryGameID = nil
        games = []
        artworkRevisions = [:]
        selection = nil
        query.pageIndex = 0
        catalogLoaded = false
        errorMessage = nil
        status = "Loading cloud games…"
        task = Task {
            defer { loading = false; task = nil }
            do {
                games = try await service.games()
                catalogLoaded = true
                if !categories.contains(query.category) { query.category = "" }
                status = "\(games.count) cloud games"
            }
            catch { fail(error) }
        }
    }

    func start(_ game: CloudGame) {
        guard !ownsSession && !loading && !sleeping, games.contains(game), let service else { return }
        guard game.access.playable else {
            errorMessage = game.access.entitled == false
                ? "This account has no entitlement for this game. Check ownership or subscription, then refresh the library."
                : "Access has not been verified. Refresh the library before starting this game."
            return
        }
        let launchPreferences = streamPreferences
        activeStreamPreferences = launchPreferences
        ownsSession = true
        cancelRequested = false
        ready = false
        errorMessage = nil
        activeGame = game.name
        activeGameID = game.id
        retryGameID = nil
        lastVideoDiagnostics = nil
        lastStreamReport = nil
        status = "Starting \(game.name)…"
        task = Task {
            do {
                // Do not cancel a creation POST: retain the returned handle so it can be deleted.
                handle = try await service.create(title: game.id, preferences: launchPreferences)
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
                        if let signaling = service as? any CloudSignaling {
                            let connection = CloudVideoConnection(framePacing: launchPreferences.framePacing)
                            self.connection = connection
                            connection.cyclePerformanceOverlay = { [weak library = self] in library?.cyclePerformanceOverlay?() }
                            connection.controllerEnabled = controllerEnabled
                            connection.keyboardEnabled = keyboardEnabled
                            connection.playbackFocused = playbackFocused
                            connection.configureAudio(muted: audioMuted, volume: audioVolume)
                            displayVideo?(connection.video)
                            try await connection.run(service: signaling, session: handle!) { [weak self] message in
                                self?.status = message
                            }
                            await cleanup()
                            return
                        }
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
                if case CloudError.rejected(_, "NoEntitlement") = error,
                   let index = games.firstIndex(where: { $0.id == game.id }) {
                    games[index].access.entitled = false
                    selection = nil
                }
                if !cancelRequested { retryGameID = game.id; fail(error) }
                if handle != nil { await cleanup() }
                else {
                    // A failed POST can have reached the service. Do not claim confirmed cleanup.
                    ownsSession = false
                    activeStreamPreferences = nil
                    activeGame = nil
                    activeGameID = nil
                    retryGameID = nil // Unknown allocation: do not offer an automatic retry shortcut.
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
        // Release local media/input now, even if signaling is awaiting an HTTP callback.
        connection?.close()
        // Creation and polling complete naturally so returned handles can be deleted.
        if ready { task?.cancel() }
        else if task == nil { task = Task { await cleanup() } }
    }

    private func cleanup() async {
        guard let service, let handle else { return }
        ending = true
        ready = false
        connection?.close()
        if let connection {
            lastVideoDiagnostics = connection.video.diagnosticsText()
            lastStreamReport = connection.video.diagnosticReport()
        }
        connection = nil
        displayVideo?(nil)
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
            activeGameID = nil
            activeStreamPreferences = nil
            status = retryGameID == nil ? "Session ended" : "Session ended — ready to retry"
        } else { status = "Session cleanup failed — retry End Session before quitting." }
    }

    private func fail(_ error: Error) {
        errorMessage = (error as? CloudError)?.localizedDescription ?? (error as? AuthError)?.localizedDescription ?? (error as? StreamError)?.localizedDescription ?? "The cloud operation failed. Please try again."
        status = "Cloud operation failed"
    }
}

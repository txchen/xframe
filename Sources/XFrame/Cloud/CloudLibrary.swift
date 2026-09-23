import Foundation
import Observation

@Observable @MainActor
final class CloudLibrary {
    enum GameLoadAction {
        case load, loading, refresh, retry
        var title: String {
            switch self {
            case .load: "Load Games"
            case .loading: "Loading games…"
            case .refresh: "Refresh Games"
            case .retry: "Retry Loading Games"
            }
        }
    }
    enum Termination: Equatable { case idle, ending, failed(String), ended, unconfirmed }
    private(set) var termination: Termination = .idle {
        didSet { if oldValue != termination { terminationChanged?(termination) } }
    }
    @ObservationIgnored var terminationChanged: ((Termination) -> Void)?
    @ObservationIgnored var requestEndSession: (() -> Void)?
    @ObservationIgnored var audioChanged: (() -> Void)?
    var query = GameLibraryQuery() { didSet { if oldValue != query { rebuildPage() } } }
    var search: String {
        get { query.search }
        set { updateQuery { $0.search = newValue } }
    }
    private(set) var favorites: Set<String> { didSet { rebuildPage() } }
    private(set) var catalogLoaded = false
    var gameLoadAction: GameLoadAction {
        if loading { return .loading }
        if catalogLoaded { return .refresh }
        return errorMessage == nil ? .load : .retry
    }
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
    var showingConsoles = false
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
    private(set) var consoles: [HomeConsole] = []
    private(set) var loadingConsoles = false
    private(set) var consoleStatus = "Refresh consoles to check the LAN."
    private(set) var consoleError: String?
    @ObservationIgnored private var homeService: (any HomeServing)?
    @ObservationIgnored private var consoleTask: Task<Void, Never>?
    private(set) var sessionSource: CloudService.Source = .cloud
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
        inputDefaults.set(audioMuted, forKey: "XFrame.AudioMuted")
        inputDefaults.set(audioVolume, forKey: "XFrame.AudioVolume")
        connection?.configureAudio(muted: audioMuted, volume: audioVolume)
        audioChanged?()
    }
    var controllerEnabled = false {
        didSet {
            inputDefaults.set(controllerEnabled, forKey: "XFrame.ControllerEnabled")
            connection?.controllerEnabled = controllerEnabled
        }
    }
    var rumbleEnabled = true {
        didSet {
            inputDefaults.set(rumbleEnabled, forKey: "XFrame.RumbleEnabled")
            connection?.rumbleEnabled = rumbleEnabled
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
    var rumbleStatus: String {
        if !rumbleEnabled { return "Controller vibration off" }
        return connection?.rumbleStatus ?? "Controller haptics available during a stream"
    }
    @ObservationIgnored private var service: (any SessionServing)?
    @ObservationIgnored private var handle: URL?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cancelRequested = false
    func exportFrameTimingSample() {
        guard let report = connection?.video.diagnosticReport() ?? lastStreamReport else {
            viewError = "Start a stream before exporting a frame timing sample."
            return
        }
        do {
            diagnosticDocument = try StreamDiagnosticDocument(report: report)
            exportingDiagnostics = true
        } catch { viewError = "Could not prepare frame timing sample." }
    }

    @ObservationIgnored private var connection: CloudVideoConnection?
    @ObservationIgnored var showPlaybackSettings: (() -> Void)?
    @ObservationIgnored var settingsGamepad: ((GamepadSnapshot) -> Void)?
    var playbackSettingsVisible = false { didSet { connection?.playbackSettingsVisible = playbackSettingsVisible } }
    @ObservationIgnored var displayVideo: ((LiveVideo?) -> Void)?
    @ObservationIgnored private let sleep: @Sendable () async throws -> Void
    @ObservationIgnored private let inputDefaults: UserDefaults

    init(favoritesStore: GameFavoritesStore = GameFavoritesStore(defaults: .standard),
         preferencesStore: CloudStreamPreferencesStore = .init(defaults: .standard),
         inputDefaults: UserDefaults = .standard,
         sleep: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }) {
        self.preferencesStore = preferencesStore
        self.inputDefaults = inputDefaults
        controllerEnabled = inputDefaults.bool(forKey: "XFrame.ControllerEnabled")
        rumbleEnabled = inputDefaults.object(forKey: "XFrame.RumbleEnabled") as? Bool ?? true
        audioMuted = inputDefaults.bool(forKey: "XFrame.AudioMuted")
        let storedVolume = inputDefaults.object(forKey: "XFrame.AudioVolume") as? Double ?? 1
        audioVolume = storedVolume.isFinite ? min(1, max(0, storedVolume)) : 1
        streamPreferences = preferencesStore.load()
        self.favoritesStore = favoritesStore
        favorites = favoritesStore.load()
        self.sleep = sleep
    }

    func reset() {
        guard !ownsSession && !loading && !loadingConsoles else { return }
        retryGameID = nil
        games = []
        artworkRevisions = [:]
        catalogLoaded = false
        query = GameLibraryQuery()
        selection = nil
        service = nil
        homeService = nil
        consoles = []
        consoleError = nil
        errorMessage = nil
        viewError = nil
        lastVideoDiagnostics = nil
        lastStreamReport = nil
        status = "Load games after signing in."
    }

    func loadConsoles(using service: any HomeServing) {
        guard !ownsSession && !loadingConsoles else { return }
        homeService = service
        loadingConsoles = true
        consoles = []
        consoleError = nil
        consoleStatus = "Checking associated consoles and the LAN…"
        consoleTask = Task {
            defer { loadingConsoles = false; consoleTask = nil }
            do {
                let associated = try await service.consoles()
                let discovered = await ConsoleDiscovery.discover()
                let ids = Set(discovered.map { $0.liveID.lowercased() })
                consoles = associated.map { item in
                    var copy = item
                    copy.local = ids.contains(item.id.lowercased())
                    return copy
                }
                consoleStatus = "\(consoles.count) associated consoles · \(consoles.filter(\.local).count) on this LAN"
                if consoles.contains(where: { !$0.homeServiceChecked }) {
                    consoleStatus += " · streaming availability could not be checked"
                }
            } catch {
                consoleError = error.localizedDescription
                consoleStatus = "Could not refresh consoles"
            }
        }
    }

    func wake(_ console: HomeConsole) {
        guard !ownsSession && !loadingConsoles && console.standby,
              consoles.contains(console), let homeService else { return }
        loadingConsoles = true
        consoleError = nil
        consoleStatus = "Sending wake command…"
        consoleTask = Task {
            defer { loadingConsoles = false; consoleTask = nil }
            do {
                try await homeService.wake(console.id)
                // A successful command is not a successful LAN discovery or a connect request.
                for _ in 0..<12 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .seconds(2))
                    let available = await ConsoleDiscovery.discover()
                    if available.contains(where: { $0.liveID.caseInsensitiveCompare(console.id) == .orderedSame }) {
                        consoles = consoles.map { item in
                            guard item.id == console.id else { return item }
                            var awake = item
                            awake.local = true
                            awake = HomeConsole(id: awake.id, name: awake.name, model: awake.model,
                                                powerState: "On", local: true, inHomeService: awake.inHomeService)
                            return awake
                        }
                        consoleStatus = "Console is available on this LAN. Click Connect to start."
                        return
                    }
                }
                consoleStatus = "Wake sent; console is not yet visible on this LAN. Refresh to check again."
            } catch {
                consoleError = error.localizedDescription
                consoleStatus = "Could not wake console"
            }
        }
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
        launch(id: game.id, name: game.name, service: service, source: .cloud)
    }

    func startConsole(_ console: HomeConsole) {
        guard !ownsSession && !loading && !loadingConsoles && !sleeping,
              let current = consoles.first(where: { $0.id == console.id }), current.local,
              current.inHomeService, !current.standby, let homeService else { return }
        loadingConsoles = true
        consoleStatus = "Checking local console presence before connecting…"
        consoleTask = Task {
            defer { loadingConsoles = false; consoleTask = nil }
            let discovered = await ConsoleDiscovery.discover()
            guard discovered.contains(where: { $0.liveID.caseInsensitiveCompare(current.id) == .orderedSame }) else {
                consoles = consoles.map { item in
                    guard item.id == current.id else { return item }
                    var missing = item; missing.local = false; return missing
                }
                consoleStatus = "Console is no longer visible on this LAN. Refresh and try again."
                return
            }
            guard !Task.isCancelled else { return }
            loadingConsoles = false
            launch(id: current.id, name: current.name, service: homeService, source: .home)
        }
    }

    private func launch(id: String, name: String, service: any SessionServing, source: CloudService.Source) {
        // Console sessions have a fixed 1080p profile; cloud quality and language do not apply.
        let launchPreferences = source == .home
            ? CloudStreamPreferences(quality: .standard, language: .english, framePacing: streamPreferences.framePacing)
            : streamPreferences
        activeStreamPreferences = launchPreferences
        sessionSource = source
        self.service = service
        ownsSession = true
        termination = .idle
        cancelRequested = false
        ready = false
        errorMessage = nil
        activeGame = name
        activeGameID = source == .cloud ? id : nil
        retryGameID = nil
        lastVideoDiagnostics = nil
        lastStreamReport = nil
        status = source == .home ? "Connecting to \(name)…" : "Starting \(name)…"
        task = Task { [self] in
            do {
                // Do not cancel a creation POST: retain the returned handle so it can be deleted.
                handle = try await service.create(title: id, preferences: launchPreferences)
                if cancelRequested { await cleanup(); return }
                let deadline = ContinuousClock.now.advanced(by: .seconds(600))
                var connected = false
                while ContinuousClock.now < deadline {
                    guard let current = handle else { throw CloudError.response }
                    let state = try await service.state(at: current)
                    if let transfer = state.transferUri {
                        guard CloudService.trusted(transfer) else { throw CloudError.response }
                        handle = try CloudService.sessionURL(current.path, relativeTo: transfer, source: source)
                    }
                    if cancelRequested { await cleanup(); return }
                    switch state.state {
                    case "WaitingForResources": status = source == .home ? "Waiting for the Xbox…" : "Queued — waiting for a cloud console…"
                    case "Provisioning": status = source == .home ? "Preparing console stream…" : "Starting the cloud game…"
                    case "ReadyToConnect":
                        status = source == .home ? "Authorizing console stream…" : "Authorizing the cloud console…"
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
                            let connection = CloudVideoConnection(framePacing: launchPreferences.framePacing, requireLocalMedia: source == .home)
                            self.connection = connection
                            connection.showPlaybackSettings = { [weak library = self] in library?.showPlaybackSettings?() }
                            connection.settingsGamepad = { [weak library = self] state in library?.settingsGamepad?(state) }
                            connection.playbackSettingsVisible = playbackSettingsVisible
                            connection.controllerEnabled = controllerEnabled
                            connection.rumbleEnabled = rumbleEnabled
                            connection.keyboardEnabled = keyboardEnabled
                            connection.playbackFocused = playbackFocused
                            connection.configureAudio(muted: audioMuted, volume: audioVolume)
                            if source == .home {
                                connection.localPathChanged = { [weak self, weak connection] verified in
                                    guard let self else { return }
                                    self.displayVideo?(verified ? connection?.video : nil)
                                }
                            } else { displayVideo?(connection.video) }
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
                   source == .cloud, let index = games.firstIndex(where: { $0.id == id }) {
                    games[index].access.entitled = false
                    selection = nil
                }
                if !cancelRequested { retryGameID = source == .cloud ? id : nil; fail(error) }
                if handle != nil { await cleanup() }
                else {
                    // A failed POST can have reached the service. Do not claim confirmed cleanup.
                    ownsSession = false
                    activeStreamPreferences = nil
                    activeGame = nil
                    activeGameID = nil
                    retryGameID = nil // Unknown allocation: do not offer an automatic retry shortcut.
                    status = "Start failed; no session address was received. Server allocation could not be confirmed."
                    ending = false
                    task = nil
                    termination = .unconfirmed
                }
            }
        }
    }

    func end() {
        guard ownsSession && !ending else { return }
        cancelRequested = true
        ending = true
        status = sessionSource == .home ? "Disconnecting from Xbox…" : "Ending session…"
        // Release local media/input now, even if signaling is awaiting an HTTP callback.
        connection?.close()
        termination = .ending
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
        termination = .ending
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
            status = sessionSource == .home ? "Disconnected — Xbox and game remain on" :
                retryGameID == nil ? "Session ended" : "Session ended — ready to retry"
            termination = .ended
        } else {
            status = "Session cleanup failed — retry before quitting."
            termination = .failed(errorMessage ?? "The cloud service could not confirm session cleanup.")
        }
    }

    private func fail(_ error: Error) {
        errorMessage = (error as? CloudError)?.localizedDescription ?? (error as? AuthError)?.localizedDescription ?? (error as? StreamError)?.localizedDescription ?? "The streaming operation failed. Please try again."
        status = sessionSource == .home ? "Console stream failed" : "Cloud operation failed"
    }
}

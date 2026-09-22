import Foundation
import Testing
@testable import XFrame

private let cloudGame = CloudGame(id: "TEST", name: "Test Game", productID: "PRODUCT", access: .init(entitled: true))
private let sessionURL = URL(string: "https://test.gssv-play-prod.xboxlive.com/v5/sessions/cloud/test-session")!

@Test @MainActor func controllerPreferenceSurvivesLibraryRecreationWithoutRestoringFocus() throws {
    let suite = "XFrameTests.Controller.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = CloudLibrary(inputDefaults: defaults)
    #expect(!first.controllerEnabled)
    first.controllerEnabled = true
    first.playbackFocused = true
    let restored = CloudLibrary(inputDefaults: defaults)
    #expect(restored.controllerEnabled)
    #expect(!restored.playbackFocused)
    restored.playbackFocused = true
    restored.playbackFocused = false
    #expect(CloudLibrary(inputDefaults: defaults).controllerEnabled)
    restored.controllerEnabled = false
    #expect(!CloudLibrary(inputDefaults: defaults).controllerEnabled)
}

private actor FakeCloud: CloudServing {
    var creates = 0
    var launches: [CloudStreamPreferences] = []
    var deletes = 0
    var connects = 0
    var failDelete = false
    let states: [String]
    let deleteDelay: Duration
    let catalog: [CloudGame]
    var index = 0
    init(states: [String] = ["Provisioned"], failDelete: Bool = false, catalog: [CloudGame] = [cloudGame], deleteDelay: Duration = .zero) {
        self.deleteDelay = deleteDelay
        self.states = states; self.failDelete = failDelete; self.catalog = catalog
    }
    func games() async throws -> [CloudGame] { catalog }
    func create(title: String, preferences: CloudStreamPreferences) async throws -> URL {
        creates += 1
        launches.append(preferences)
        try await Task.sleep(for: .milliseconds(30))
        return sessionURL
    }
    func state(at: URL) async throws -> CloudSessionState {
        let state = states[min(index, states.count - 1)]
        index += 1
        return CloudSessionState(state: state, transferUri: nil)
    }
    func configuration(at: URL) async throws {}
    func connect(at: URL) async throws { connects += 1 }
    func end(at: URL) async throws {
        deletes += 1
        try await Task.sleep(for: deleteDelay)
        if failDelete { failDelete = false; throw CloudError.network }
    }
}

@Test @MainActor func librarySearchClearsHiddenSelectionAndKeepsFavorites() async throws {
    let suite = "XFrameTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let library = CloudLibrary(favoritesStore: GameFavoritesStore(defaults: defaults), inputDefaults: defaults)
    library.load(using: FakeCloud())
    try await eventually { !library.loading }
    #expect(library.catalogLoaded)
    let computations = library.pageComputations
    for _ in 0..<100 { _ = library.page; _ = library.categories; _ = library.selectedGame }
    library.setAudio(muted: true, volume: 0.5)
    #expect(library.pageComputations == computations)
    library.reloadArtwork(for: cloudGame)
    #expect(library.artworkRevisions[cloudGame.id] == 1)
    #expect(library.pageComputations == computations)
    library.moveSelection(by: 1)
    #expect(library.selectedGame == cloudGame)
    library.moveSelection(by: -1)
    #expect(library.selectedGame == cloudGame)
    library.selection = cloudGame.id
    #expect(library.selectedGame == cloudGame)
    library.toggleFavorite(cloudGame)
    library.search = "missing"
    #expect(library.selection == nil && library.selectedGame == nil)
    #expect(library.page.total == 0)
    library.reset()
    #expect(!library.catalogLoaded && library.query.search.isEmpty)
    #expect(library.artworkRevisions.isEmpty)
    #expect(library.favorites.contains(cloudGame.id))
    library.load(using: FakeCloud())
    try await eventually { !library.loading }
    library.updateQuery { $0.favoritesOnly = true }
    library.selection = cloudGame.id
    library.toggleFavorite(cloudGame)
    #expect(library.page.total == 0 && library.selectedGame == nil && library.selection == nil)
}

@MainActor private func eventually(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !predicate() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    #expect(predicate())
}

@Test @MainActor func cachedLibraryInvalidatesAndKeyboardSelectionStaysOnPage() async throws {
    let games = (0..<30).map { CloudGame(id: "\($0)", name: "Game \($0)", productID: nil, access: .init(entitled: true)) }
    let library = try await loaded(FakeCloud(catalog: games))
    let before = library.pageComputations
    library.moveSelection(by: 1)
    #expect(library.selectedGame?.id == "0")
    library.moveSelection(by: 1)
    #expect(library.selectedGame?.id == "1")
    #expect(library.pageComputations == before)
    library.goToPage(1)
    #expect(library.selection == nil && library.page.games.count == 6)
    library.moveSelection(by: -1)
    #expect(library.selectedGame?.id == "29")
    library.moveSelection(by: 1)
    #expect(library.selectedGame?.id == "29")
    library.search = "Game 27"
    #expect(library.page.index == 0 && library.page.total == 1 && library.selection == nil)
    library.moveSelection(by: 1)
    #expect(library.selectedGame?.id == "27")
    library.search = "absent"
    library.moveSelection(by: -1)
    #expect(library.selectedGame == nil)
}

@MainActor private func loaded(_ fake: FakeCloud) async throws -> CloudLibrary {
    let library = CloudLibrary(sleep: { try await Task.sleep(for: .milliseconds(5)) })
    library.load(using: fake)
    try await eventually { !library.loading }
    return library
}

@Test @MainActor func deniedAndUnknownGamesNeverCreateCloudSessions() async throws {
    for access in [CloudGameAccess(), CloudGameAccess(entitled: false)] {
        let game = CloudGame(id: "DENIED", name: "Denied", productID: nil, access: access)
        let fake = FakeCloud(catalog: [game])
        let library = try await loaded(fake)
        #expect(library.page.total == 0)
        library.updateQuery { $0.access = .all }
        #expect(library.page.total == 1)
        library.start(game)
        #expect(!library.ownsSession)
        #expect(library.errorMessage != nil)
        #expect(await fake.creates == 0)
    }
}

@Test @MainActor func cancelDuringCreationDeletesReturnedSession() async throws {
    let fake = FakeCloud()
    let library = try await loaded(fake)
    library.start(cloudGame)
    library.end()
    try await eventually { !library.ownsSession }
    #expect(await fake.creates == 1)
    #expect(await fake.deletes == 1)
    #expect(library.status == "Session ended")
}

@Test @MainActor func readySessionCanEndWithoutCanceledCleanup() async throws {
    let fake = FakeCloud(states: ["WaitingForResources", "Provisioning", "ReadyToConnect", "ReadyToConnect", "Provisioned"])
    let library = try await loaded(fake)
    library.start(cloudGame)
    library.start(cloudGame)
    try await eventually { library.ready }
    library.end()
    try await eventually { !library.ownsSession }
    #expect(await fake.creates == 1)
    #expect(await fake.deletes == 1)
    #expect(await fake.connects == 1)
}

@Test @MainActor func failedDeletionRetainsOwnershipAndCanRetry() async throws {
    let fake = FakeCloud(failDelete: true)
    let library = try await loaded(fake)
    library.start(cloudGame)
    try await eventually { library.ready }
    library.end()
    try await eventually { library.status.contains("cleanup failed") }
    #expect(library.ownsSession)
    library.start(cloudGame)
    library.end()
    try await eventually { !library.ownsSession }
    #expect(await fake.creates == 1)
    #expect(await fake.deletes == 2)
}

@Test @MainActor func unsupportedStateIsCleanedUp() async throws {
    let fake = FakeCloud(states: ["UnknownFutureState"])
    let library = try await loaded(fake)
    library.start(cloudGame)
    try await eventually { !library.ownsSession }
    #expect(library.errorMessage != nil)
    #expect(await fake.deletes == 1)
}

@Test @MainActor func resetRemovesPreviousAccountCatalog() async throws {
    let fake = FakeCloud()
    let library = try await loaded(fake)
    library.reset()
    library.start(cloudGame)
    #expect(library.games.isEmpty)
    #expect(!library.ownsSession)
    #expect(await fake.creates == 0)
}

@Test func sessionAddressesRejectUntrustedDestinations() throws {
    let host = URL(string: "https://test.gssv-play-prod.xboxlive.com/")!
    #expect(try CloudService.sessionURL("/v5/sessions/cloud/abc", relativeTo: host).lastPathComponent == "abc")
    for path in ["https://evil.invalid/v5/sessions/cloud/abc", "https://xboxlive.com.evil.invalid/v5/sessions/cloud/abc",
                 "/v5/sessions/cloud/active", "/v5/sessions/cloud/abc?secret=yes", "/v5/sessions/cloud/abc/state"] {
        #expect(throws: (any Error).self) { try CloudService.sessionURL(path, relativeTo: host) }
    }
}

@Test @MainActor func streamPreferencesAreCapturedAtStartAndChangesApplyToNextSession() async throws {
    let suite = "XFrameTests.LaunchPreferences.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = CloudStreamPreferencesStore(defaults: defaults)
    let fake = FakeCloud()
    let library = CloudLibrary(preferencesStore: store)
    library.load(using: fake)
    try await eventually { !library.loading }
    let first = CloudStreamPreferences(quality: .hq, language: .simplifiedChinese, framePacing: .lowLatency)
    let second = CloudStreamPreferences(quality: .standard, language: .traditionalChinese)
    library.streamPreferences = first
    library.start(cloudGame)
    library.streamPreferences = second // Before the async create task gets to run.
    #expect(library.activeStreamPreferences == first)
    library.end()
    try await eventually { !library.ownsSession }
    #expect(await fake.launches == [first])
    #expect(library.activeStreamPreferences == nil)
    library.start(cloudGame)
    #expect(library.activeStreamPreferences == second)
    library.end()
    try await eventually { !library.ownsSession }
    #expect(await fake.launches == [first, second])
    library.reset()
    #expect(library.streamPreferences == second)
    #expect(CloudLibrary(preferencesStore: store).streamPreferences == second)
}

@Test @MainActor func sleepDuringCreationRetainsHandleForCleanupAndWakeDoesNotLaunch() async throws {
    let fake = FakeCloud()
    let library = try await loaded(fake)
    library.start(cloudGame)
    library.systemWillSleep()
    library.systemWillSleep()
    try await eventually { !library.ownsSession }
    #expect(library.retryGame == nil)
    library.start(cloudGame) // Cannot allocate while sleeping.
    #expect(!library.ownsSession)
    library.systemDidWake()
    #expect(library.retryGame == cloudGame)
    #expect(await fake.creates == 1)
    #expect(await fake.deletes == 1)
    library.retry()
    library.end()
    try await eventually { !library.ownsSession }
    #expect(await fake.creates == 2)
    #expect(await fake.deletes == 2)
}

@Test @MainActor func wakeRetriesFailedSleepCleanupBeforeAllowingPlay() async throws {
    let fake = FakeCloud(failDelete: true)
    let library = try await loaded(fake)
    library.start(cloudGame)
    try await eventually { library.ready }
    library.systemWillSleep()
    try await eventually { library.status.contains("cleanup failed") }
    library.retry()
    #expect(library.ownsSession && library.retryGame == nil)
    library.systemDidWake()
    try await eventually { !library.ownsSession }
    #expect(library.retryGame == cloudGame)
    #expect(await fake.creates == 1)
    #expect(await fake.deletes == 2)
}

@Test @MainActor func failedStartOffersRetryOnlyAfterCleanupAndResetClearsIt() async throws {
    let fake = FakeCloud(states: ["Failed"], failDelete: true)
    let library = try await loaded(fake)
    library.start(cloudGame)
    try await eventually { library.status.contains("cleanup failed") }
    #expect(library.retryGame == nil)
    library.retry()
    #expect(await fake.creates == 1)
    library.end()
    try await eventually { !library.ownsSession }
    #expect(library.retryGame == cloudGame)
    library.reset()
    #expect(library.retryGame == nil)
}

@Test @MainActor func audioPreferencesRestoreMuteAndVolumeIndependently() throws {
    let suite = "XFrameTests.Audio.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let library = CloudLibrary(inputDefaults: defaults)
    #expect(library.audioVolume == 1 && !library.audioMuted)
    library.setAudio(muted: true, volume: 0.4)
    let restored = CloudLibrary(inputDefaults: defaults)
    #expect(restored.audioVolume == 0.4 && restored.audioMuted)
    restored.setAudio(muted: true, volume: 0.6)
    let adjusted = CloudLibrary(inputDefaults: defaults)
    #expect(adjusted.audioVolume == 0.6 && adjusted.audioMuted)
    adjusted.setAudio(muted: false, volume: adjusted.audioVolume)
    #expect(CloudLibrary(inputDefaults: defaults).audioVolume == 0.6)
    #expect(!CloudLibrary(inputDefaults: defaults).audioMuted)
    adjusted.setAudio(muted: false, volume: 10)
    #expect(CloudLibrary(inputDefaults: defaults).audioVolume == 1)
    adjusted.setAudio(muted: true, volume: .nan)
    #expect(CloudLibrary(inputDefaults: defaults).audioVolume == 0)
}

@Test @MainActor func terminationRemainsPendingUntilServiceConfirmsAndSuppressesDuplicateRequests() async throws {
    let fake = FakeCloud(deleteDelay: .milliseconds(150))
    let library = try await loaded(fake)
    var transitions: [CloudLibrary.Termination] = []
    library.terminationChanged = { transitions.append($0) }
    library.start(cloudGame)
    try await eventually { library.ready }
    library.end()
    #expect(library.ending && library.termination == .ending && library.ownsSession)
    for _ in 0..<10 { library.end() }
    try await Task.sleep(for: .milliseconds(30))
    #expect(library.ownsSession && library.termination == .ending)
    library.playbackFocused = false
    try await eventually { !library.ownsSession }
    #expect(transitions == [.ending, .ended])
    #expect(await fake.deletes == 1)
}

@Test @MainActor func cleanupFailureKeepsPanelRetryStateUntilRetrySucceeds() async throws {
    let fake = FakeCloud(failDelete: true, deleteDelay: .milliseconds(50))
    let library = try await loaded(fake)
    var transitions: [CloudLibrary.Termination] = []
    library.terminationChanged = { transitions.append($0) }
    library.start(cloudGame)
    try await eventually { library.ready }
    library.end()
    try await eventually { !library.ending }
    guard case .failed = library.termination else { Issue.record("Missing retry state"); return }
    #expect(library.ownsSession && !library.ready)
    library.end()
    library.end()
    try await eventually { !library.ownsSession }
    #expect(transitions.count == 4)
    #expect(transitions.last == .ended)
    #expect(await fake.deletes == 2)
}

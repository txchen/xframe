import Foundation
import Testing
@testable import XFrame

private let cloudGame = CloudGame(id: "TEST", name: "Test Game", productID: "PRODUCT")
private let sessionURL = URL(string: "https://test.gssv-play-prod.xboxlive.com/v5/sessions/cloud/test-session")!

private actor FakeCloud: CloudServing {
    var creates = 0
    var deletes = 0
    var connects = 0
    var failDelete = false
    let states: [String]
    var index = 0
    init(states: [String] = ["Provisioned"], failDelete: Bool = false) {
        self.states = states; self.failDelete = failDelete
    }
    func games() async throws -> [CloudGame] { [cloudGame] }
    func create(title: String) async throws -> URL {
        creates += 1
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
        if failDelete { failDelete = false; throw CloudError.network }
    }
}

@MainActor private func eventually(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !predicate() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    #expect(predicate())
}

@MainActor private func loaded(_ fake: FakeCloud) async throws -> CloudLibrary {
    let library = CloudLibrary(sleep: { try await Task.sleep(for: .milliseconds(5)) })
    library.load(using: fake)
    try await eventually { !library.loading }
    return library
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

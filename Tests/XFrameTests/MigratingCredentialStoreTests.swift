import Foundation
import Testing
@testable import XFrame

@MainActor
private final class FakeStore: CredentialStore {
    var token: String?
    var failSave = false, failLoad = false, failDelete = false, corruptReadBack = false
    private(set) var saves = 0
    init(_ token: String? = nil) { self.token = token }
    func load() throws -> String? {
        if failLoad { throw AuthError.keychain(-25293) }
        return corruptReadBack && token != nil ? "corrupt" : token
    }
    func save(_ refreshToken: String) throws {
        saves += 1
        if failSave { throw AuthError.keychain(-25308) }
        token = refreshToken
    }
    func delete() throws {
        if failDelete { throw AuthError.keychain(-25244) }
        token = nil
    }
    var storageDescription: String { "fake" }
}

@Test @MainActor func legacyFileMigratesIntoKeychainAfterReadBack() throws {
    let keychain = FakeStore(), file = FakeStore("legacy-token")
    let store = MigratingCredentialStore(primary: keychain, legacy: file)
    #expect(try store.load() == "legacy-token")
    #expect(keychain.token == "legacy-token")
    #expect(file.token == nil)
    #expect(!store.usingLegacyFile)
    try store.save("rotated")
    #expect(keychain.token == "rotated")
    #expect(file.token == nil)
    #expect(try store.load() == "rotated")
}

@Test @MainActor func failedKeychainWriteKeepsTheOnlyLegacyCredential() throws {
    let keychain = FakeStore(), file = FakeStore("legacy-token")
    keychain.failSave = true
    let store = MigratingCredentialStore(primary: keychain, legacy: file)
    #expect(try store.load() == "legacy-token")
    #expect(file.token == "legacy-token")
    #expect(store.usingLegacyFile)
    // Rotation stays durable in the file while Keychain is unavailable.
    try store.save("rotated")
    #expect(file.token == "rotated")
    // A later save retries migration and removes the file once Keychain works.
    keychain.failSave = false
    try store.save("rotated-again")
    #expect(keychain.token == "rotated-again")
    #expect(file.token == nil)
    #expect(!store.usingLegacyFile)
}

@Test @MainActor func mismatchedReadBackDoesNotDeleteLegacyFile() throws {
    let keychain = FakeStore(), file = FakeStore("legacy-token")
    keychain.corruptReadBack = true
    let store = MigratingCredentialStore(primary: keychain, legacy: file)
    #expect(try store.load() == "legacy-token")
    #expect(file.token == "legacy-token")
    #expect(store.usingLegacyFile)
    // The file remains authoritative over a stale Keychain value on next launch.
    keychain.corruptReadBack = false
    keychain.token = "stale"
    let relaunched = MigratingCredentialStore(primary: keychain, legacy: file)
    #expect(try relaunched.load() == "legacy-token")
    #expect(keychain.token == "legacy-token")
    #expect(file.token == nil)
}

@Test @MainActor func newAccountsNeverFallBackToPlaintext() throws {
    let keychain = FakeStore(), file = FakeStore()
    keychain.failSave = true
    let store = MigratingCredentialStore(primary: keychain, legacy: file)
    #expect(try store.load() == nil)
    #expect(throws: (any Error).self) { try store.save("new-token") }
    #expect(file.token == nil)
    #expect(file.saves == 0)
}

@Test @MainActor func unsafeLegacyFileDoesNotShadowMigratedCredential() throws {
    let keychain = FakeStore("keychain-token"), file = FakeStore("legacy")
    file.failLoad = true
    #expect(try MigratingCredentialStore(primary: keychain, legacy: file).load() == "keychain-token")
    keychain.token = nil
    #expect(throws: (any Error).self) { try MigratingCredentialStore(primary: keychain, legacy: file).load() }
}

@Test @MainActor func signOutRemovesBothStoresAndReportsFailure() throws {
    let keychain = FakeStore("a"), file = FakeStore("b")
    file.failDelete = true
    let store = MigratingCredentialStore(primary: keychain, legacy: file)
    #expect(throws: (any Error).self) { try store.delete() }
    #expect(keychain.token == nil)
    file.failDelete = false
    try store.delete()
    #expect(file.token == nil)
}

@Test @MainActor func onlyTeamSignedBuildsUseKeychain() {
    #expect(CredentialStorage.store(teamIdentifier: nil) is FileCredentialStore)
    #expect(CredentialStorage.store(teamIdentifier: "") is FileCredentialStore)
    #expect(CredentialStorage.store(teamIdentifier: "24HJJ8KB69") is MigratingCredentialStore)
    // The test host is not the XFrame bundle, so tests never touch the real Keychain.
    #expect(CredentialStorage.makeDefault() is FileCredentialStore)
}

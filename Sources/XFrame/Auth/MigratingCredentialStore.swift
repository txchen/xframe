import Foundation
import Security

// Keychain is authoritative for Apple team-signed builds. A legacy plaintext
// file exists only until one migration succeeds: its token is written to the
// primary store and read back before the file is removed. If migration fails,
// the file stays the working credential and later saves retry migration, so the
// only usable sign-in is never deleted. Accounts without a legacy file never
// fall back to plaintext.
@MainActor
final class MigratingCredentialStore: CredentialStore {
    private let primary: any CredentialStore
    private let legacy: any CredentialStore
    private(set) var usingLegacyFile = false

    init(primary: any CredentialStore, legacy: any CredentialStore) {
        self.primary = primary
        self.legacy = legacy
    }

    var storageDescription: String {
        usingLegacyFile
            ? "Keychain migration has not completed; sign-in remains in the previous owner-only, unencrypted local file. XFrame retries migration on the next sign-in refresh. Sign Out removes both."
            : "Sign-in is saved in your macOS login Keychain. Sign Out removes it; browser sign-in is unchanged."
    }

    func load() throws -> String? {
        let legacyToken: String?
        do { legacyToken = try legacy.load() } catch {
            // An unsafe legacy file must not shadow a migrated credential.
            if let token = try primary.load() { return token }
            throw error
        }
        guard let legacyToken else {
            usingLegacyFile = false
            return try primary.load()
        }
        migrate(legacyToken)
        return legacyToken
    }

    func save(_ refreshToken: String) throws {
        if usingLegacyFile {
            migrate(refreshToken)
            if usingLegacyFile { try legacy.save(refreshToken) }
        } else {
            try primary.save(refreshToken)
        }
    }

    func delete() throws {
        var failure: (any Error)?
        do { try primary.delete() } catch { failure = error }
        do { try legacy.delete() } catch { failure = failure ?? error }
        if let failure { throw failure }
        usingLegacyFile = false
    }

    private func migrate(_ token: String) {
        do {
            try primary.save(token)
            guard try primary.load() == token else { throw AuthError.invalidResponse("Keychain migration") }
            try legacy.delete()
            usingLegacyFile = false
        } catch {
            usingLegacyFile = true
        }
    }
}

enum CredentialStorage {
    // Legacy Keychain partitions bind changed builds to an Apple team only when
    // one exists; otherwise every rebuild prompts. Unteamed development builds
    // keep the owner-only file. See .scratch/keychain-access/diagnosis.md.
    // The bundle check keeps hosts such as the test runner, which carry their
    // own team signature, away from the user's real Keychain.
    @MainActor static func makeDefault() -> any CredentialStore {
        guard Bundle.main.bundleIdentifier == "win.xframe.app" else { return FileCredentialStore() }
        return store(teamIdentifier: currentTeamIdentifier())
    }

    @MainActor static func store(teamIdentifier: String?) -> any CredentialStore {
        guard let teamIdentifier, !teamIdentifier.isEmpty else { return FileCredentialStore() }
        return MigratingCredentialStore(primary: KeychainCredentialStore(), legacy: FileCredentialStore())
    }

    static func currentTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess, let info = info as? [String: Any] else { return nil }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

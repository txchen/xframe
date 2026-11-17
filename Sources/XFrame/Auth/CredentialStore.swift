import Foundation
import Security

@MainActor
protocol CredentialStore {
    func load() throws -> String?
    func save(_ refreshToken: String) throws
    func delete() throws
    var storageDescription: String { get }
}

@MainActor
struct KeychainCredentialStore: CredentialStore {
    // A new service name: items left by earlier self-signed development builds
    // are bound to their code hash, and reading them would prompt.
    static let service = "win.xframe.app.microsoft-sign-in"
    var storageDescription: String { "Sign-in is saved in your macOS login Keychain." }
    let account: String
    init(account: String = "microsoft-refresh-\(XboxAuthService.clientID)") { self.account = account }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AuthError.keychain(status) }
        guard let data = result as? Data else { throw AuthError.invalidResponse("Saved sign-in") }
        if data == Self.signedOut { return nil }
        guard let token = String(data: data, encoding: .utf8), !token.isEmpty else { throw AuthError.invalidResponse("Saved sign-in") }
        return token
    }

    func save(_ refreshToken: String) throws {
        let value = [kSecValueData as String: Data(refreshToken.utf8)]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(value) { _, value in value }
            item[kSecAttrLabel as String] = "XFrame Microsoft sign-in"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let add = SecItemAdd(item as CFDictionary, nil)
            guard add == errSecSuccess else { throw AuthError.keychain(add) }
        } else if status != errSecSuccess { throw AuthError.keychain(status) }
    }

    // Legacy Keychain lets later team-signed builds read and update an item but
    // only the exact creating binary delete it (errSecInvalidOwnerEdit). Sign-out
    // then overwrites the token with this marker; the next sign-in reuses the
    // item. Empty data is not usable: the update succeeds without changing it.
    static let signedOut = Data("xframe-signed-out".utf8)
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        guard status == errSecInvalidOwnerEdit else { throw AuthError.keychain(status) }
        let erase = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Self.signedOut] as CFDictionary)
        guard erase == errSecSuccess else { throw AuthError.keychain(erase) }
        guard try load() == nil else { throw AuthError.keychain(errSecInvalidOwnerEdit) }
    }
}

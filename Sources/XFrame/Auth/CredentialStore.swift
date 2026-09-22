import Foundation
import Security

@MainActor
protocol CredentialStore {
    func load() throws -> String?
    func save(_ refreshToken: String) throws
    func delete() throws
}

@MainActor
struct KeychainCredentialStore: CredentialStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "win.txchen.xframe.xcloud",
         kSecAttrAccount as String: "microsoft-refresh-\(XboxAuthService.clientID)",
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
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw AuthError.invalidResponse("Saved sign-in")
        }
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

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AuthError.keychain(status) }
    }
}

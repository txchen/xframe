// Read-only diagnostic. Never requests password data or permits UI prompts.
import Foundation
import Security

SecKeychainSetUserInteractionAllowed(false)
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "win.txchen.xframe.xcloud",
    kSecAttrAccount as String: "microsoft-refresh-1f907974-e22b-4810-a9de-d9647380c97e",
    kSecReturnRef as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne
]
var item: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &item)
print("Item metadata status: \(status)")
guard status == errSecSuccess, let item else { exit(1) }
var access: SecAccess?
let accessStatus = SecKeychainItemCopyAccess(item as! SecKeychainItem, &access)
print("Access metadata status: \(accessStatus)")
guard accessStatus == errSecSuccess, let access else { exit(1) }
var list: CFArray?
guard SecAccessCopyACLList(access, &list) == errSecSuccess, let acls = list as? [SecACL] else { exit(1) }
for (index, acl) in acls.enumerated() {
    var apps: CFArray?
    var label: CFString?
    var selector = SecKeychainPromptSelector()
    let result = SecACLCopyContents(acl, &apps, &label, &selector)
    print("ACL \(index): status=\(result), authorizations=\(String(describing: SecACLCopyAuthorizations(acl))), prompt=\(selector)")
    if let label {
        let text = label as String
        if text.hasPrefix("3c3f786d6c"), text.count.isMultiple(of: 2) {
            var bytes = Data()
            var offset = text.startIndex
            while offset < text.endIndex {
                let end = text.index(offset, offsetBy: 2)
                guard let byte = UInt8(text[offset..<end], radix: 16) else { exit(1) }
                bytes.append(byte); offset = end
            }
            if let plist = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any] {
                print("Partition restrictions: \(plist["Partitions"] ?? "Unknown")")
            }
        } else { print("ACL description: \(label)") }
    }
    for app in (apps as? [SecTrustedApplication] ?? []) {
        var data: CFData?
        if SecTrustedApplicationCopyData(app, &data) == errSecSuccess, let data {
            print("Trusted application metadata: \(String(decoding: data as Data, as: UTF8.self))")
        }
    }
}

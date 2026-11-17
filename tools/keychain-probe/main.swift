// Exercises XFrame's real KeychainCredentialStore with a synthetic token under a
// probe-only account. Never touches the app's sign-in item.
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: keychain-probe save|load|delete <account> [token]"); exit(2)
}
MainActor.assumeIsolated {
    let store = KeychainCredentialStore(account: args[2])
    do {
        switch args[1] {
        case "save": try store.save(args[3]); print("saved variant=\(probeVariant)")
        case "load": print("loaded=\(try store.load() ?? "<nil>") variant=\(probeVariant)")
        case "delete": try store.delete(); print("deleted variant=\(probeVariant)")
        default: exit(2)
        }
    } catch { print("error: \(error)"); exit(1) }
}

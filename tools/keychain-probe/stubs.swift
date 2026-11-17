enum AuthError: Error { case keychain(Int32), invalidResponse(String) }
enum XboxAuthService { static let clientID = "keychain-probe" }

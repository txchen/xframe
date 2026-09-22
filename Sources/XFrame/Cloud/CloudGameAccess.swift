import Foundation

/// Account-scoped service evidence, not an inference from catalog membership.
struct CloudGameAccess: Equatable, Sendable {
    var entitled: Bool? = nil
    var programs: [String] = []
    var free = false

    var playable: Bool { entitled == true }
    // These are catalog programs, not evidence of a purchase or subscription tier.
    var gamePass: Bool { programs.contains("GPULTIMATE") }
    var label: String {
        switch entitled {
        case true?: free ? "Free · Playable" : gamePass ? "Game Pass · Playable" : "Playable"
        case false?: "No entitlement"
        case nil: "Access unverified"
        }
    }
}

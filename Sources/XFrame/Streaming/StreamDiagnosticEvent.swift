import Foundation

// Deliberately limited schema: no arbitrary messages, media, tokens or addresses.
struct StreamDiagnosticEvent: Sendable {
    enum Kind: String, Sendable {
        case configured, firstFrame, idrSubmitted, badData, keyframeRequestDequeued, networkChange, stopped
    }
    let milliseconds: Int
    let kind: Kind
    let configuration: Int
    let accessUnit: Int?
    let synchronous: Bool?
    let keyframe: Bool?
    let packetsLost: Int?
    let nacks: Int?

    var line: String {
        var text = "\(milliseconds)ms \(kind.rawValue) config=\(configuration)"
        if let accessUnit { text += " unit=\(accessUnit)" }
        if let synchronous { text += synchronous ? " sync" : " async" }
        if let keyframe { text += keyframe ? " IDR" : " delta" }
        if let packetsLost { text += " lost=\(packetsLost)" }
        if let nacks { text += " nacks=\(nacks)" }
        return text
    }
}

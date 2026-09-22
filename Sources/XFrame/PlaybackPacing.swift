import Foundation
import QuartzCore

enum FramePacingMode: String, CaseIterable, Codable, Sendable {
    case balanced, lowLatency
    var title: String { self == .balanced ? "Balanced" : "Low latency (experimental)" }
    var capacity: Int { self == .balanced ? 2 : 1 }
}

struct PlaybackPacingSnapshot: Codable, Equatable, Sendable {
    var inboxReplaced = 0
    var rendererReplaced = 0
    var drawTicks = 0
    var busyTicks = 0
    var drawableMisses = 0
    var notPresented = 0
    var arrivalInterval: TimingSummary?
    var drawInterval: TimingSummary?
    var drawableWait: TimingSummary?
}

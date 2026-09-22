import Foundation

// Recognize View+Menu within 300 ms, before either button reaches the game.
// Longer individual holds remain ordinary game controls and cannot become a chord.
struct GamepadHUDShortcut {
    struct Result {
        let states: [GamepadSnapshot]
        let cycle: Bool
    }
    private enum Phase {
        case idle, waiting(GamepadButton, Double), forwarding, chord
    }
    private var phase = Phase.idle
    private let recognitionWindow = 0.3
    private let reserved: Set<GamepadButton> = [.view, .menu]

    mutating func reset() { phase = .idle }
    mutating func process(_ state: GamepadSnapshot, now: Double) -> Result {
        let held = state.buttons.intersection(reserved)
        let stripped = state.replacingButtons(state.buttons.subtracting(reserved))
        switch phase {
        case .idle:
            if held == reserved {
                phase = .chord
                return Result(states: [stripped], cycle: true)
            }
            if let button = held.first {
                phase = .waiting(button, now)
                return Result(states: [stripped], cycle: false)
            }
        case .waiting(let button, let started):
            if held == reserved && now - started <= recognitionWindow {
                phase = .chord
                return Result(states: [stripped], cycle: true)
            }
            if held == [button] && now - started < recognitionWindow {
                return Result(states: [stripped], cycle: false)
            }
            phase = held.isEmpty ? .idle : .forwarding
            if !held.contains(button) {
                // Preserve a quick standalone tap's press before its release.
                return Result(states: [stripped.replacingButtons(stripped.buttons.union([button])), state], cycle: false)
            }
        case .forwarding:
            if held.isEmpty { phase = .idle }
        case .chord:
            if held.isEmpty { phase = .idle }
            return Result(states: [stripped], cycle: false)
        }
        return Result(states: [state], cycle: false)
    }
}

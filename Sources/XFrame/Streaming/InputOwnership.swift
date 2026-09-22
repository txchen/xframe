import Foundation

// Only fresh intentional activity claims the single virtual controller.
struct InputOwnership {
    enum Device { case keyboard, controller }
    private(set) var active: Device?
    private var previous = GamepadSnapshot()

    mutating func reset(controller: GamepadSnapshot = GamepadSnapshot()) {
        active = nil
        previous = controller
    }
    mutating func claimKeyboard() -> Bool { claim(.keyboard) }
    mutating func observeController(_ state: GamepadSnapshot, enabled: Bool) -> Bool {
        defer { previous = state }
        func zone(_ value: Double) -> Int { value > 0.25 ? 1 : value < -0.25 ? -1 : 0 }
        let axes = [state.leftX, state.leftY, state.rightX, state.rightY, state.leftTrigger, state.rightTrigger]
        let old = [previous.leftX, previous.leftY, previous.rightX, previous.rightY, previous.leftTrigger, previous.rightTrigger]
        let motion = zip(axes, old).contains { zone($0.0) != 0 && zone($0.0) != zone($0.1) }
        guard enabled, !state.buttons.subtracting(previous.buttons).isEmpty || motion else { return false }
        return claim(.controller)
    }
    private mutating func claim(_ device: Device) -> Bool {
        guard active != device else { return false }
        active = device
        return true
    }
}

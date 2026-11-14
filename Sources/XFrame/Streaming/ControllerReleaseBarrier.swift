import Foundation

// Track the physical device independently of the virtual controller's owner.
// An unrelated new press must not carry a control held in a menu into the game.
struct ControllerReleaseBarrier {
    private var buttons: Set<GamepadButton> = []
    private var leftStick = false
    private var rightStick = false
    private var leftTrigger = false
    private var rightTrigger = false
    static let releaseThreshold = 0.1

    mutating func pause(_ state: GamepadSnapshot) {
        buttons = state.buttons
        leftStick = hypot(state.leftX, state.leftY) > Self.releaseThreshold
        rightStick = hypot(state.rightX, state.rightY) > Self.releaseThreshold
        leftTrigger = state.leftTrigger > Self.releaseThreshold
        rightTrigger = state.rightTrigger > Self.releaseThreshold
    }

    mutating func filter(_ state: GamepadSnapshot, accepting: Bool) -> GamepadSnapshot {
        guard accepting else { pause(state); return GamepadSnapshot() }
        buttons.formIntersection(state.buttons)
        if hypot(state.leftX, state.leftY) <= Self.releaseThreshold { leftStick = false }
        if hypot(state.rightX, state.rightY) <= Self.releaseThreshold { rightStick = false }
        if state.leftTrigger <= Self.releaseThreshold { leftTrigger = false }
        if state.rightTrigger <= Self.releaseThreshold { rightTrigger = false }
        return GamepadSnapshot(buttons: state.buttons.subtracting(buttons),
            leftX: leftStick ? 0 : state.leftX, leftY: leftStick ? 0 : state.leftY,
            rightX: rightStick ? 0 : state.rightX, rightY: rightStick ? 0 : state.rightY,
            leftTrigger: leftTrigger ? 0 : state.leftTrigger, rightTrigger: rightTrigger ? 0 : state.rightTrigger)
    }
}

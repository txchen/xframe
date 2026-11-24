import Foundation

// macOS hardware key codes: physical ANSI positions, independent of text/IME layout.
// Only the focused playback window forwards events here; no global event tap.
struct KeyboardGamepad {
    private var held: Set<UInt16> = []
    private static let buttons: [UInt16: GamepadButton] = [
        40: .a, 49: .a,           // K / Space -> A
        37: .b, 51: .b,           // L / Backspace -> B
        38: .x, 15: .x,           // J / R -> X
        34: .y, 3: .y,            // I / F -> Y
        12: .leftShoulder,        // Q -> LB
        14: .rightShoulder,       // E -> RB
        18: .up, 19: .down,       // 1 / 2 -> D-pad Up / Down
        20: .left, 21: .right,    // 3 / 4 -> D-pad Left / Right
        56: .leftThumb,           // Left Shift -> LS (Sprint)
        9: .rightThumb,           // V -> RS
        36: .menu,                // Return -> Menu
        48: .view                 // Tab -> View
    ]
    static let controls = """
    W A S D — Left stick (move)
    Arrow keys — Right stick (look)
    I / J / K / L — Y / X / A / B  (Xbox diamond)
    Space — A     Backspace — B     R — X     F — Y
    Q / E — LB / RB       U / O — LT / RT
    Left Shift — LS (sprint)       V — RS
    1 / 2 / 3 / 4 — D-pad Up / Down / Left / Right
    Return — Menu       Tab — View

    Keyboard input is enabled by default and can be toggled in View or the right-click panel.
    Both controller and keyboard can be enabled; new input switches control automatically.
    Command, Control and Option shortcuts remain available.
    """

    @discardableResult
    mutating func handle(code: UInt16, down: Bool, repeatKey: Bool = false, shortcut: Bool = false) -> Bool {
        if shortcut { release(); return false }
        guard Self.buttons[code] != nil || [0, 1, 2, 13, 123, 124, 125, 126, 32, 31].contains(code) else { return false }
        if !down { held.remove(code) }
        else if !repeatKey { held.insert(code) }
        return true
    }
    mutating func release() { held.removeAll(keepingCapacity: true) }

    var snapshot: GamepadSnapshot {
        func axis(_ negative: UInt16, _ positive: UInt16) -> Double {
            (held.contains(positive) ? 1.0 : 0) - (held.contains(negative) ? 1.0 : 0)
        }
        func stick(_ x: Double, _ y: Double) -> (Double, Double) {
            let length = max(1, hypot(x, y))
            return (x / length, y / length)
        }
        let left = stick(axis(0, 2), axis(13, 1))
        let right = stick(axis(123, 124), axis(126, 125))
        return GamepadSnapshot(buttons: Set(held.compactMap { Self.buttons[$0] }),
            leftX: left.0, leftY: left.1, rightX: right.0, rightY: right.1,
            leftTrigger: held.contains(32) ? 1 : 0, rightTrigger: held.contains(31) ? 1 : 0)
    }
}

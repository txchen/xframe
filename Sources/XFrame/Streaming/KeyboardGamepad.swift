import Foundation

// macOS hardware key codes: physical ANSI positions, independent of text/IME layout.
// Only the focused playback window forwards events here; no global event tap.
struct KeyboardGamepad {
    private var held: Set<UInt16> = []
    private static let buttons: [UInt16: GamepadButton] = [
        38: .a, 49: .a, 40: .b, 32: .x, 34: .y,
        12: .leftShoulder, 14: .rightShoulder,
        3: .left, 17: .up, 4: .right, 5: .down,
        37: .leftThumb, 31: .rightThumb, 36: .menu, 48: .view
    ]
    static let controls = """
    WASD — Left stick (move)
    Arrow keys — Right stick (look)
    J / Space — A       K — B       U — X       I — Y
    Q / E — LB / RB       Z / C — LT / RT
    F / T / H / G — D-pad left / up / right / down
    L / O — Left / right stick click
    Return — Menu       Tab — View

    Enable Keyboard Input in View, then focus the playback window.
    Both input devices can be enabled; new input switches control automatically.
    Uses physical key positions. Sticks and triggers are digital, not analog.
    Command, Control and Option shortcuts remain available.
    Release and press keys again after switching windows or recovering a stream.
    """

    @discardableResult
    mutating func handle(code: UInt16, down: Bool, repeatKey: Bool = false, shortcut: Bool = false) -> Bool {
        if shortcut { release(); return false }
        guard Self.buttons[code] != nil || [0, 1, 2, 13, 123, 124, 125, 126, 6, 8].contains(code) else { return false }
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
            leftTrigger: held.contains(6) ? 1 : 0, rightTrigger: held.contains(8) ? 1 : 0)
    }
}

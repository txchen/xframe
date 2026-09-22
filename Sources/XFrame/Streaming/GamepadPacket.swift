import Foundation

// Offline groundwork only: not connected to controller discovery or WebRTC.
// State uses browser-oriented Y (positive down); the wire encoder negates Y.
// A future GameController adapter must convert its positive-up Y exactly once.
enum GamepadButton: UInt16, CaseIterable, Sendable {
    case nexus = 0x0002, menu = 0x0004, view = 0x0008
    case a = 0x0010, b = 0x0020, x = 0x0040, y = 0x0080
    case up = 0x0100, down = 0x0200, left = 0x0400, right = 0x0800
    case leftShoulder = 0x1000, rightShoulder = 0x2000
    case leftThumb = 0x4000, rightThumb = 0x8000

    var physicality: UInt32 {
        switch self {
        case .nexus: 0x0400
        case .menu: 0x0010
        case .view: 0x0020
        case .a: 0x1000
        case .b: 0x2000
        case .x: 0x4000
        case .y: 0x8000
        case .up: 0x0001
        case .down: 0x0002
        case .left: 0x0004
        case .right: 0x0008
        case .leftShoulder: 0x0100
        case .rightShoulder: 0x0200
        case .leftThumb: 0x0040
        case .rightThumb: 0x0080
        }
    }
}

struct GamepadSnapshot: Sendable, Equatable {
    let buttons: Set<GamepadButton>
    let leftX, leftY, rightX, rightY, leftTrigger, rightTrigger: Double
    init(buttons: Set<GamepadButton> = [], leftX: Double = 0, leftY: Double = 0,
         rightX: Double = 0, rightY: Double = 0, leftTrigger: Double = 0, rightTrigger: Double = 0) {
        func bounded(_ value: Double, minimum: Double) -> Double {
            value.isFinite ? min(1, max(minimum, value)) : 0
        }
        self.buttons = buttons
        self.leftX = bounded(leftX, minimum: -1); self.leftY = bounded(leftY, minimum: -1)
        self.rightX = bounded(rightX, minimum: -1); self.rightY = bounded(rightY, minimum: -1)
        self.leftTrigger = bounded(leftTrigger, minimum: 0); self.rightTrigger = bounded(rightTrigger, minimum: 0)
    }
    var physicality: UInt32 {
        var mask = buttons.reduce(UInt32(0)) { $0 | $1.physicality }
        if leftX != 0 || leftY != 0 { mask |= 0x000c0000 }
        if rightX != 0 || rightY != 0 { mask |= 0x00300000 }
        if leftTrigger != 0 { mask |= 0x00010000 }
        if rightTrigger != 0 { mask |= 0x00020000 }
        return mask
    }
}

struct GamepadPacketEncoder {
    enum EncodingError: Error { case invalidTimestamp }
    private(set) var sequence: UInt32 = 0
    init(lastSequence: UInt32 = 0) { sequence = lastSequence }

    mutating func reset() { sequence = 0 }
    mutating func packet(_ state: GamepadSnapshot, timestampMS: Double) throws -> Data {
        let next = sequence &+ 1
        let data = try Self.encode(state, sequence: next, timestampMS: timestampMS)
        sequence = next
        return data
    }
    static func encode(_ state: GamepadSnapshot, sequence: UInt32, timestampMS: Double) throws -> Data {
        guard timestampMS.isFinite, timestampMS >= 0 else { throw EncodingError.invalidTimestamp }
        var data = Data()
        data.reserveCapacity(38)
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        append(UInt16(2)); append(sequence); append(timestampMS.bitPattern)
        append(UInt8(1)); append(UInt8(0)) // One physical gamepad, index zero.
        append(state.buttons.reduce(UInt16(0)) { $0 | $1.rawValue })
        for axis in [state.leftX, -state.leftY, state.rightX, -state.rightY] {
            append(Int16(axis * 32767)) // Truncation toward zero, matching the reference.
        }
        append(UInt16(state.leftTrigger * 65535)); append(UInt16(state.rightTrigger * 65535))
        append(state.physicality); append(UInt32(0)) // No virtual inputs.
        return data
    }
}

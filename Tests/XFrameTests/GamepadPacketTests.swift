import Foundation
import Testing
@testable import XFrame

private func bytes(_ hex: String) -> Data { Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! }) }

@Test func gamepadPacketsMatchPinnedReferenceGoldenBytes() throws {
    let neutral = try GamepadPacketEncoder.encode(GamepadSnapshot(), sequence: 1, timestampMS: 1000)
    #expect(neutral == bytes("02 00 01 00 00 00 00 00 00 00 00 40 8f 40 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"))
    let pressed = try GamepadPacketEncoder.encode(GamepadSnapshot(buttons: [.a]), sequence: 1, timestampMS: 1000)
    #expect(pressed == bytes("02 00 01 00 00 00 00 00 00 00 00 40 8f 40 01 00 10 00 00 00 00 00 00 00 00 00 00 00 00 00 00 10 00 00 00 00 00 00"))
    #expect(pressed.count == 38)
}

@Test func gamepadAnalogBoundsYDirectionAndPhysicalityAreExplicit() throws {
    let snapshot = GamepadSnapshot(leftX: 0.5, leftY: -0.5, rightX: -2, rightY: 2,
                                   leftTrigger: 0.5, rightTrigger: 2)
    let packet = try GamepadPacketEncoder.encode(snapshot, sequence: 0, timestampMS: 0)
    #expect(packet.subdata(in: 18..<30) == bytes("ff 3f ff 3f 01 80 01 80 ff 7f ff ff"))
    #expect(packet.subdata(in: 30..<38) == bytes("00 00 3f 00 00 00 00 00"))
    let invalid = GamepadSnapshot(leftX: .nan, leftY: .infinity, rightX: -.infinity, leftTrigger: -1)
    #expect(invalid == GamepadSnapshot())
    #expect(invalid.physicality == 0)
}

@Test func gamepadButtonsUseIndependentWireAndPhysicalityMasks() throws {
    let physical: [UInt32] = [0x400, 0x10, 0x20, 0x1000, 0x2000, 0x4000, 0x8000,
                              1, 2, 4, 8, 0x100, 0x200, 0x40, 0x80]
    for (index, button) in GamepadButton.allCases.enumerated() {
        let packet = try GamepadPacketEncoder.encode(GamepadSnapshot(buttons: [button]), sequence: 1, timestampMS: 0)
        let mask = UInt16(packet[16]) | (UInt16(packet[17]) << 8)
        #expect(mask == UInt16(2) << index)
        #expect(GamepadSnapshot(buttons: [button]).physicality == physical[index])
    }
}

@Test func gamepadSnapshotsReleaseAndSequenceResetsWithoutSending() throws {
    var encoder = GamepadPacketEncoder()
    let pressed = GamepadSnapshot(buttons: [.a])
    let packet = try encoder.packet(pressed, timestampMS: 1)
    let neutral = try encoder.packet(GamepadSnapshot(), timestampMS: 2)
    #expect(packet[16] == 0x10 && neutral[16] == 0)
    #expect(pressed.buttons == [.a])
    #expect(encoder.sequence == 2)
    #expect(throws: GamepadPacketEncoder.EncodingError.self) { try encoder.packet(pressed, timestampMS: .nan) }
    #expect(encoder.sequence == 2)
    encoder.reset()
    #expect(encoder.sequence == 0)
    let boundary = try GamepadPacketEncoder.encode(GamepadSnapshot(), sequence: .max, timestampMS: 0)
    #expect(boundary.subdata(in: 2..<6) == bytes("ff ff ff ff"))
    var wrapping = GamepadPacketEncoder(lastSequence: .max)
    #expect(try wrapping.packet(GamepadSnapshot(), timestampMS: 1).subdata(in: 2..<6) == bytes("00 00 00 00"))
    #expect(wrapping.sequence == 0)
}

import Foundation

// Transport-independent bounded input scheduler. All calls are serialized by its owner.
struct GamepadInput {
    private(set) var encoder = GamepadPacketEncoder()
    private(set) var queue: [GamepadSnapshot] = []
    private(set) var armed = false
    private var ownsInput = false
    private var latest = GamepadSnapshot()
    private(set) var needsNeutral = true
    static let capacity = 32

    mutating func update(_ state: GamepadSnapshot, ownsInput: Bool) {
        if !ownsInput {
            if self.ownsInput { release() }
            self.ownsInput = false
            return
        }
        self.ownsInput = true
        if !armed {
            // Do not carry a held button across focus/device/session boundaries.
            guard state == GamepadSnapshot() else { return }
            armed = true
        }
        guard state != latest else { return }
        latest = state
        // Analog motion can arrive faster than the wire tick. Coalesce within
        // one button/trigger edge, but retain even very short digital presses.
        if let tail = queue.last, tail.buttons == state.buttons,
           (tail.leftTrigger > 0) == (state.leftTrigger > 0),
           (tail.rightTrigger > 0) == (state.rightTrigger > 0) {
            queue[queue.count - 1] = state
            return
        }
        if queue.count >= Self.capacity {
            release()
            return
        }
        queue.append(state)
    }

    mutating func release() {
        queue.removeAll(keepingCapacity: true)
        latest = GamepadSnapshot()
        armed = false
        needsNeutral = true
    }

    // Commit the sequence and dequeue only when the transport accepts the bytes.
    @discardableResult
    mutating func send(timestampMS: Double, transport: (Data) -> Bool) -> Bool {
        let state = needsNeutral ? GamepadSnapshot() : (queue.first ?? latest)
        var candidate = encoder
        guard let packet = try? candidate.packet(state, timestampMS: timestampMS), transport(packet) else { return false }
        encoder = candidate
        if needsNeutral { needsNeutral = false }
        else if !queue.isEmpty { queue.removeFirst() }
        return true
    }
}

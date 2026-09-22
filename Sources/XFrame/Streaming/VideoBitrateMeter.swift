import Foundation

// Per-session video RTP payload throughput, in decimal Mbps. Native stats use µs.
struct VideoBitrateMeter {
    private var previous: (id: String, bytes: Double, time: Double)?

    mutating func sample(bytes: Double?, timestampUS: Double?, streamID: String?) -> Double? {
        guard let bytes, bytes.isFinite, bytes >= 0,
              let time = timestampUS, time.isFinite, time >= 0,
              let id = streamID, !id.isEmpty else {
            previous = nil
            return nil
        }
        guard let old = previous, old.id == id else {
            previous = (id, bytes, time)
            return nil
        }
        guard time > old.time else { return nil }
        guard bytes >= old.bytes else {
            previous = (id, bytes, time)
            return nil
        }
        previous = (id, bytes, time)
        // bits / microsecond is numerically equal to megabits / second.
        let value = (bytes - old.bytes) * 8 / (time - old.time)
        return value.isFinite && value >= 0 ? value : nil
    }
}

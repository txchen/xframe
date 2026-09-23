import Foundation
import Darwin
import Security

struct DiscoveredConsole: Sendable, Equatable {
    let liveID: String
    let name: String
}

// SmartGlass discovery is a LAN presence check, separate from the account service's power state.
enum ConsoleDiscovery {
    static let request = Data([0xdd, 0x00, 0x00, 0x0a, 0x00, 0x00,
                               0, 0, 0, 0, 0, 3, 0, 0, 0, 2])

    static func discover() async -> [DiscoveredConsole] {
        await Task.detached(priority: .userInitiated) { probe() }.value
    }

    private static func probe() -> [DiscoveredConsole] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { Darwin.close(fd) }
        var enabled: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else { return [] }
        func sendDiscovery() {
            for address in ["255.255.255.255", "239.255.255.250"] {
                var destination = sockaddr_in()
                destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                destination.sin_family = sa_family_t(AF_INET)
                destination.sin_port = UInt16(5050).bigEndian
                _ = address.withCString { inet_pton(AF_INET, $0, &destination.sin_addr) }
                _ = request.withUnsafeBytes { bytes in
                    withUnsafePointer(to: &destination) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddr in
                            sendto(fd, bytes.baseAddress, bytes.count, 0, sockaddr, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
            }
        }
        var found: [String: DiscoveredConsole] = [:]
        let interfaces = LocalMediaPath.interfaces()
        let deadline = Date().addingTimeInterval(1.5)
        var nextSend = Date.distantPast
        while Date() < deadline {
            if Date() >= nextSend {
                sendDiscovery()
                nextSend = Date().addingTimeInterval(0.5)
            }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let milliseconds = Int32(max(0, min(250, Int(deadline.timeIntervalSinceNow * 1000))))
            guard poll(&descriptor, 1, milliseconds) > 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var sender = sockaddr_in()
            var senderSize = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    recvfrom(fd, &buffer, buffer.count, 0, address, &senderSize)
                }
            }
            let source = sender.sin_addr.s_addr.bigEndian
            guard count > 0, LocalMediaPath.isPrivateIPv4(source),
                  interfaces.contains(where: { $0.mask != 0 && source & $0.mask == $0.address & $0.mask }) else { continue }
            if let console = parse(Data(buffer.prefix(count))) { found[console.liveID] = console }
        }
        return Array(found.values)
    }

    static func parse(_ packet: Data) -> DiscoveredConsole? {
        let bytes = [UInt8](packet)
        guard bytes.count >= 30, bytes[0] == 0xdd, bytes[1] == 0x01,
              Int(bytes[2]) * 256 + Int(bytes[3]) == bytes.count - 6 else { return nil }
        var offset = 6 + 8
        func string() -> String? {
            guard offset + 2 <= bytes.count else { return nil }
            let length = Int(bytes[offset]) * 256 + Int(bytes[offset + 1])
            offset += 2
            guard length > 0, length < 256, offset + length + 1 <= bytes.count,
                  bytes[offset + length] == 0 else { return nil }
            let value = String(bytes: bytes[offset..<offset + length], encoding: .utf8)
            offset += length + 1
            return value
        }
        guard let name = string(), string() != nil, offset + 6 <= bytes.count else { return nil }
        offset += 4 // Last error.
        let certificateLength = Int(bytes[offset]) * 256 + Int(bytes[offset + 1])
        offset += 2
        guard certificateLength > 0, certificateLength < 3000,
              offset + certificateLength <= bytes.count,
              let certificate = SecCertificateCreateWithData(nil, Data(bytes[offset..<offset + certificateLength]) as CFData),
              let liveID = SecCertificateCopySubjectSummary(certificate) as String?,
              !liveID.isEmpty, liveID.count < 256 else { return nil }
        return DiscoveredConsole(liveID: liveID, name: name)
    }
}

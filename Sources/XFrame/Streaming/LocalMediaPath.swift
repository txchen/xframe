import Foundation
import Darwin

struct LocalMediaPath: Sendable {
    struct Interface: Sendable, Equatable {
        let address: UInt32
        let mask: UInt32
    }

    static func ipv4(_ text: String) -> UInt32? {
        var address = in_addr()
        guard text.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else { return nil }
        return address.s_addr.bigEndian
    }

    static func isPrivateIPv4(_ address: UInt32) -> Bool {
        (address & 0xff00_0000) == 0x0a00_0000 ||
        (address & 0xfff0_0000) == 0xac10_0000 ||
        (address & 0xffff_0000) == 0xc0a8_0000 ||
        (address & 0xffff_0000) == 0xa9fe_0000
    }

    static func isLocal(remote: String, local: String, remoteType: String, localType: String,
                        interfaces: [Interface]) -> Bool {
        guard remoteType == "host", localType == "host",
              let remoteIP = ipv4(remote), let localIP = ipv4(local),
              isPrivateIPv4(remoteIP), isPrivateIPv4(localIP) else { return false }
        return interfaces.contains { interface in
            interface.address == localIP && interface.mask != 0 &&
            remoteIP & interface.mask == localIP & interface.mask
        }
    }

    static func interfaces() -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let start = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [Interface] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = start
        while let item = cursor {
            let entry = item.pointee
            defer { cursor = entry.ifa_next }
            guard let address = entry.ifa_addr, let mask = entry.ifa_netmask,
                  address.pointee.sa_family == AF_INET, mask.pointee.sa_family == AF_INET,
                  entry.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("eth") else { continue }
            let ip = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr.bigEndian
            let netmask = UnsafeRawPointer(mask).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr.bigEndian
            result.append(Interface(address: ip, mask: netmask))
        }
        return result
    }
}

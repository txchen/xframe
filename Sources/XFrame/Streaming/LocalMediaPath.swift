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

    enum Side { case local, remote }
    enum Refusal: String, Error, Sendable { case malformed, unsupportedAddress, unsupportedTransport, relay, outsideLAN, noInterface }
    struct Endpoint: Sendable, Equatable {
        let address: UInt32
        let port: UInt16
        let kind: String
        private init(address: UInt32, port: UInt16, kind: String) {
            self.address = address; self.port = port; self.kind = kind
        }
        static func parse(address: String, port: Int, kind: String, protocolName: String) throws -> Self {
            guard protocolName.lowercased() == "udp" else { throw Refusal.unsupportedTransport }
            guard ["host", "srflx", "prflx", "relay"].contains(kind), (1...65535).contains(port) else { throw Refusal.malformed }
            guard kind != "relay" else { throw Refusal.relay }
            guard let ip = ipv4(address), isPrivateIPv4(ip) else { throw Refusal.unsupportedAddress }
            return Self(address: ip, port: UInt16(port), kind: kind)
        }
    }
    static func usable(_ ip: UInt32, on interface: Interface) -> Bool {
        let mask = interface.mask
        let inverse = ~mask
        guard mask != 0, inverse > 1, inverse & (inverse &+ 1) == 0,
              isPrivateIPv4(interface.address), isPrivateIPv4(ip) else { return false }
        let host = ip & inverse
        return ip & mask == interface.address & mask && host != 0 && host != inverse
    }
    static func admit(_ endpoint: Endpoint, side: Side, interfaces: [Interface]) throws {
        guard !interfaces.isEmpty else { throw Refusal.noInterface }
        guard interfaces.contains(where: { usable(endpoint.address, on: $0) && (side == .remote || $0.address == endpoint.address) }) else { throw Refusal.outsideLAN }
    }
    static func candidate(_ text: String, side: Side, interfaces: [Interface]) throws -> Endpoint {
        let raw = text.hasPrefix("a=") ? String(text.dropFirst(2)) : text
        let parts = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 8, parts[0].hasPrefix("candidate:"), parts[0].count > 10,
              let component = UInt16(parts[1]), component == 1 || component == 2,
              UInt32(parts[3]) != nil, let port = Int(parts[5]), parts[6] == "typ",
              (parts.count - 8) % 2 == 0 else { throw Refusal.malformed }
        for index in stride(from: 8, to: parts.count, by: 2) {
            guard parts[index] != "typ" else { throw Refusal.malformed }
        }
        let endpoint = try Endpoint.parse(address: parts[4], port: port, kind: parts[7], protocolName: parts[2])
        try admit(endpoint, side: side, interfaces: interfaces)
        return endpoint
    }
    static func filterSDP(_ sdp: String, side: Side, interfaces: [Interface]) throws -> String {
        let separator = sdp.contains("\r\n") ? "\r\n" : "\n"
        return try sdp.components(separatedBy: separator).filter { line in
            if line.hasPrefix("a=candidate:") {
                return (try? candidate(line, side: side, interfaces: interfaces)) != nil
            }
            if line.hasPrefix("a=remote-candidates:") || line.hasPrefix("a=rtcp:") { return false }
            if line.hasPrefix("c=") && line != "c=IN IP4 0.0.0.0" {
                let parts = line.split(separator: " ")
                guard parts.count == 3, parts[0] == "c=IN", parts[1] == "IP4",
                      let endpoint = try? Endpoint.parse(address: String(parts[2]), port: 9, kind: "host", protocolName: "udp"),
                      (try? admit(endpoint, side: side, interfaces: interfaces)) != nil else { throw Refusal.unsupportedAddress }
            }
            if line.hasPrefix("a=alt:") { throw Refusal.malformed }
            return true
        }.joined(separator: separator)
    }
    static func isLocal(remote: String, local: String, remoteType: String, localType: String,
                        interfaces: [Interface]) -> Bool {
        guard let remote = try? Endpoint.parse(address: remote, port: 1, kind: remoteType, protocolName: "udp"),
              let local = try? Endpoint.parse(address: local, port: 1, kind: localType, protocolName: "udp") else { return false }
        return verify(local: local, remote: remote, interfaces: interfaces)
    }
    static func verify(local: Endpoint, remote: Endpoint, interfaces: [Interface]) -> Bool {
        interfaces.contains { $0.address == local.address && usable(local.address, on: $0) && usable(remote.address, on: $0) }
    }

    struct Stats: Sendable {
        let id: String
        let type: String
        let strings: [String: String]
        let port: Int?
    }
    static func selectedPath(_ stats: [Stats], interfaces: [Interface]) -> Bool? {
        let byID = Dictionary(stats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let transports = stats.filter { $0.type == "transport" }
        guard !transports.isEmpty else { return nil }
        let media = stats.filter { $0.type == "inbound-rtp" }
        guard media.allSatisfy({ record in
            guard let id = record.strings["transportId"] else { return false }
            return transports.contains { $0.id == id }
        }) else { return nil }
        var missing = false
        for transport in transports {
            guard let pairID = transport.strings["selectedCandidatePairId"],
                  let pair = byID[pairID], pair.type == "candidate-pair",
                  pair.strings["state"] == "succeeded" || pair.strings["state"] == "in-progress",
                  let localID = pair.strings["localCandidateId"], let local = byID[localID], local.type == "local-candidate",
                  let remoteID = pair.strings["remoteCandidateId"], let remote = byID[remoteID], remote.type == "remote-candidate" else { missing = true; continue }
            func endpoint(_ record: Stats) throws -> Endpoint? {
                guard let address = record.strings["address"] ?? record.strings["ip"],
                      let kind = record.strings["candidateType"], let port = record.port,
                      let protocolName = record.strings["protocol"] else { return nil }
                return try Endpoint.parse(address: address, port: port, kind: kind, protocolName: protocolName)
            }
            do {
                guard let localEndpoint = try endpoint(local), let remoteEndpoint = try endpoint(remote) else { missing = true; continue }
                if !verify(local: localEndpoint, remote: remoteEndpoint, interfaces: interfaces) { return false }
            } catch { return false }
        }
        return missing ? nil : true
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
                  entry.ifa_flags & UInt32(IFF_UP) != 0,
                  entry.ifa_flags & UInt32(IFF_RUNNING) != 0 else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("eth") else { continue }
            let ip = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr.bigEndian
            let netmask = UnsafeRawPointer(mask).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr.bigEndian
            result.append(Interface(address: ip, mask: netmask))
        }
        return result
    }
}

struct LocalPathGate: Sendable {
    enum State: Equatable { case waiting, verified, rejected, closed }
    private(set) var state: State = .waiting
    private(set) var epoch: UInt64 = 0
    private var connected = false
    private var deadline: Double?
    private var lastEvidence: Double?
    var isVerified: Bool { state == .verified }
    mutating func transportChanged(_ connected: Bool, now: Double) {
        guard state != .closed, state != .rejected, self.connected != connected else { return }
        self.connected = connected
        epoch &+= 1
        state = .waiting
        lastEvidence = nil
        deadline = connected ? now + 6 : nil
    }
    mutating func observe(_ valid: Bool?, epoch: UInt64, now: Double) {
        guard self.epoch == epoch, connected, state != .closed, state != .rejected else { return }
        tick(now: now)
        guard state != .rejected else { return }
        if let valid {
            state = valid ? .verified : .rejected
            if valid { lastEvidence = now; deadline = nil }
        } else {
            if state == .verified { deadline = now + 6 }
            state = .waiting
            lastEvidence = nil
        }
    }
    mutating func tick(now: Double) {
        guard connected, state != .closed, state != .rejected else { return }
        if let lastEvidence, now - lastEvidence >= 2.5 {
            state = .waiting
            self.lastEvidence = nil
            deadline = lastEvidence + 2.5 + 6
        }
        if let deadline, now >= deadline { state = .rejected }
    }
    mutating func close() { epoch &+= 1; state = .closed; connected = false }
}

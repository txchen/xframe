import Foundation
import Testing
@testable import XFrame

private let lanInterfaces = [LocalMediaPath.Interface(address: LocalMediaPath.ipv4("192.168.1.10")!, mask: 0xffff_ff00)]
private func candidate(_ address: String, kind: String = "host", protocolName: String = "UDP", port: Int = 1234) -> String {
    "candidate:1 1 \(protocolName) 123 \(address) \(port) typ \(kind)"
}

@Test func localCandidateAdmissionUsesActualEndpointAndSide() throws {
    for kind in ["host", "srflx", "prflx"] {
        #expect(throws: Never.self) { try LocalMediaPath.candidate(candidate("192.168.1.20", kind: kind), side: .remote, interfaces: lanInterfaces) }
        #expect(throws: Never.self) { try LocalMediaPath.candidate(candidate("192.168.1.10", kind: kind), side: .local, interfaces: lanInterfaces) }
    }
    for address in ["8.8.8.8", "127.0.0.1", "192.168.1.0", "192.168.1.255", "192.168.2.20", "foo.local", "::1", "0.0.0.0"] {
        #expect(throws: (any Error).self) { try LocalMediaPath.candidate(candidate(address), side: .remote, interfaces: lanInterfaces) }
    }
    for text in [candidate("192.168.1.20", kind: "relay"), candidate("192.168.1.20", protocolName: "TCP"), candidate("192.168.1.20", port: 0), "candidate:bad", candidate("8.8.8.8") + " raddr 192.168.1.20 rport 1234"] {
        #expect(throws: (any Error).self) { try LocalMediaPath.candidate(text, side: .remote, interfaces: lanInterfaces) }
    }
    #expect(throws: (any Error).self) { try LocalMediaPath.candidate(candidate("192.168.1.20"), side: .local, interfaces: lanInterfaces) }
    for mask: UInt32 in [0, 0xff00_ff00, 0xffff_ffff, 0xffff_fffe] {
        #expect(!LocalMediaPath.isLocal(remote: "192.168.1.20", local: "192.168.1.10", remoteType: "host", localType: "host", interfaces: [.init(address: LocalMediaPath.ipv4("192.168.1.10")!, mask: mask)]))
    }
}

@Test func localSDPAndTrickleApplySameAdmission() throws {
    let good = "a=" + candidate("192.168.1.20", kind: "prflx")
    let bad = "a=" + candidate("8.8.8.8")
    let sdp = ["v=0", "m=video 9 UDP/TLS/RTP/SAVPF 96", "c=IN IP4 0.0.0.0", "a=mid:video", good, bad, "a=remote-candidates:1 8.8.8.8 1234", "a=rtcp:9 IN IP4 8.8.8.8", ""].joined(separator: "\r\n")
    let filtered = try LocalMediaPath.filterSDP(sdp, side: .remote, interfaces: lanInterfaces)
    #expect(filtered == ["v=0", "m=video 9 UDP/TLS/RTP/SAVPF 96", "c=IN IP4 0.0.0.0", "a=mid:video", good, ""].joined(separator: "\r\n"))
    #expect(throws: Never.self) { try LocalMediaPath.candidate(good, side: .remote, interfaces: lanInterfaces) }
    #expect(throws: (any Error).self) { try LocalMediaPath.candidate(bad, side: .remote, interfaces: lanInterfaces) }
    #expect(try LocalMediaPath.filterSDP("v=0\r\na=mid:0\r\n", side: .local, interfaces: []) == "v=0\r\na=mid:0\r\n")
    #expect(throws: (any Error).self) { try LocalMediaPath.filterSDP("c=IN IP4 8.8.8.8", side: .remote, interfaces: lanInterfaces) }
}

@Test func selectedPairMustUseSelectedLocalSubnet() {
    let both = lanInterfaces + [.init(address: LocalMediaPath.ipv4("10.0.0.10")!, mask: 0xffff_ff00)]
    #expect(!LocalMediaPath.isLocal(remote: "10.0.0.20", local: "192.168.1.10", remoteType: "prflx", localType: "host", interfaces: both))
    #expect(LocalMediaPath.isLocal(remote: "10.0.0.20", local: "10.0.0.10", remoteType: "srflx", localType: "prflx", interfaces: both))
}

@Test func gateRevokesMissingEvidenceAndAllowsRepeatedRecovery() {
    var gate = LocalPathGate()
    gate.transportChanged(true, now: 0)
    var edges: [Bool] = []
    for (time, evidence): (Double, Bool?) in [(1, true), (2, nil), (3, true), (4, nil), (5, true)] {
        let old = gate.isVerified
        gate.observe(evidence, epoch: gate.epoch, now: time)
        if old != gate.isVerified { edges.append(gate.isVerified) }
    }
    #expect(edges == [true, false, true, false, true])
    gate.tick(now: 7.5)
    #expect(!gate.isVerified)
    gate.tick(now: 13.5)
    #expect(gate.state == .rejected)
}

@Test func gateIgnoresLateEvidenceAndDuplicateConnectedEvents() {
    var gate = LocalPathGate()
    gate.transportChanged(true, now: 0)
    let oldEpoch = gate.epoch
    gate.transportChanged(true, now: 4)
    #expect(gate.epoch == oldEpoch)
    gate.observe(nil, epoch: oldEpoch, now: 5)
    gate.tick(now: 6)
    #expect(gate.state == .rejected)
    gate.observe(true, epoch: oldEpoch, now: 6.1)
    #expect(!gate.isVerified)
    var recovery = LocalPathGate()
    recovery.transportChanged(true, now: 0)
    let stale = recovery.epoch
    recovery.observe(true, epoch: stale, now: 1)
    recovery.transportChanged(false, now: 2)
    recovery.transportChanged(true, now: 3)
    recovery.observe(true, epoch: stale, now: 3.1)
    #expect(!recovery.isVerified)
    recovery.observe(true, epoch: recovery.epoch, now: 4)
    #expect(recovery.isVerified)
    recovery.close()
    recovery.observe(true, epoch: recovery.epoch, now: 5)
    recovery.transportChanged(true, now: 6)
    #expect(recovery.state == .closed)
}

private func selectedStats(state: String = "succeeded") -> [LocalMediaPath.Stats] {
    [.init(id: "transport", type: "transport", strings: ["selectedCandidatePairId": "pair"], port: nil),
     .init(id: "pair", type: "candidate-pair", strings: ["state": state, "localCandidateId": "local", "remoteCandidateId": "remote"], port: nil),
     .init(id: "local", type: "local-candidate", strings: ["address": "192.168.1.10", "candidateType": "host", "protocol": "udp"], port: 1234),
     .init(id: "remote", type: "remote-candidate", strings: ["address": "192.168.1.20", "candidateType": "prflx", "protocol": "udp"], port: 1234)]
}

@Test func selectedTransportEvidenceAllowsBootstrapAndRejectsAmbiguity() {
    let records = selectedStats()
    #expect(LocalMediaPath.selectedPath(records, interfaces: lanInterfaces) == true)
    let inbound = LocalMediaPath.Stats(id: "video", type: "inbound-rtp", strings: ["transportId": "transport"], port: nil)
    #expect(LocalMediaPath.selectedPath(records + [inbound], interfaces: lanInterfaces) == true)
    let unknown = LocalMediaPath.Stats(id: "video", type: "inbound-rtp", strings: ["transportId": "unknown"], port: nil)
    #expect(LocalMediaPath.selectedPath(records + [unknown], interfaces: lanInterfaces) == nil)
    let incomplete = LocalMediaPath.Stats(id: "other", type: "transport", strings: [:], port: nil)
    #expect(LocalMediaPath.selectedPath(records + [incomplete], interfaces: lanInterfaces) == nil)
    #expect(LocalMediaPath.selectedPath(Array(records.dropLast()), interfaces: lanInterfaces) == nil)
    var relay = Array(records.dropLast())
    relay.append(.init(id: "remote", type: "remote-candidate", strings: ["address": "192.168.1.20", "candidateType": "relay", "protocol": "udp"], port: 1234))
    #expect(LocalMediaPath.selectedPath(relay, interfaces: lanInterfaces) == false)
    var missingProtocol = Array(records.dropLast())
    missingProtocol.append(.init(id: "remote", type: "remote-candidate", strings: ["address": "192.168.1.20", "candidateType": "host"], port: 1234))
    #expect(LocalMediaPath.selectedPath(missingProtocol, interfaces: lanInterfaces) == nil)
}

@Test func selectedPairConsentCheckKeepsPresentationVerified() {
    var gate = LocalPathGate()
    gate.transportChanged(true, now: 0)
    for (index, state) in ["succeeded", "in-progress", "succeeded"].enumerated() {
        let evidence = LocalMediaPath.selectedPath(selectedStats(state: state), interfaces: lanInterfaces)
        gate.observe(evidence, epoch: gate.epoch, now: Double(index + 1))
        #expect(gate.isVerified, "Selected LAN pair must remain verified during \(state)")
    }
    gate.transportChanged(false, now: 4)
    gate.observe(LocalMediaPath.selectedPath(selectedStats(state: "in-progress"), interfaces: lanInterfaces), epoch: gate.epoch, now: 5)
    #expect(!gate.isVerified)
}

@Test func selectedPairConsentCheckStillRejectsInvalidEndpoints() {
    let records = selectedStats(state: "in-progress")
    for strings in [
        ["address": "8.8.8.8", "candidateType": "host", "protocol": "udp"],
        ["address": "192.168.2.20", "candidateType": "host", "protocol": "udp"],
        ["address": "192.168.1.20", "candidateType": "relay", "protocol": "udp"],
        ["address": "192.168.1.20", "candidateType": "host", "protocol": "tcp"]
    ] {
        let invalid = Array(records.dropLast()) + [LocalMediaPath.Stats(id: "remote", type: "remote-candidate", strings: strings, port: 1234)]
        let evidence = LocalMediaPath.selectedPath(invalid, interfaces: lanInterfaces)
        #expect(evidence == false)
        var gate = LocalPathGate()
        gate.transportChanged(true, now: 0)
        gate.observe(true, epoch: gate.epoch, now: 1)
        gate.observe(evidence, epoch: gate.epoch, now: 2)
        #expect(gate.state == .rejected)
    }
}

@Test func selectedPairConsentCheckStillRequiresCompleteEvidence() {
    let records = selectedStats(state: "in-progress")
    var missingProtocol = Array(records.dropLast())
    missingProtocol.append(.init(id: "remote", type: "remote-candidate", strings: ["address": "192.168.1.20", "candidateType": "host"], port: 1234))
    for incomplete in [records.filter { $0.id != "local" }, Array(records.dropLast()), missingProtocol] {
        let evidence = LocalMediaPath.selectedPath(incomplete, interfaces: lanInterfaces)
        #expect(evidence == nil)
        var gate = LocalPathGate()
        gate.transportChanged(true, now: 0)
        gate.observe(true, epoch: gate.epoch, now: 1)
        gate.observe(evidence, epoch: gate.epoch, now: 2)
        #expect(!gate.isVerified)
    }
    for state in ["frozen", "waiting", "failed", "", "unknown"] {
        #expect(LocalMediaPath.selectedPath(selectedStats(state: state), interfaces: lanInterfaces) == nil)
    }
}

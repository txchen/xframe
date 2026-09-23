import Foundation
import Testing
@testable import XFrame

@Test func localMediaRequiresHostCandidatesOnSamePhysicalSubnet() {
    let interfaces = [LocalMediaPath.Interface(address: LocalMediaPath.ipv4("192.168.1.10")!, mask: 0xffff_ff00)]
    #expect(LocalMediaPath.isLocal(remote: "192.168.1.25", local: "192.168.1.10",
                                   remoteType: "host", localType: "host", interfaces: interfaces))
    for remote in ["8.8.8.8", "10.0.0.3", "192.168.2.4", "127.0.0.1", "invalid"] {
        #expect(!LocalMediaPath.isLocal(remote: remote, local: "192.168.1.10",
                                        remoteType: "host", localType: "host", interfaces: interfaces))
    }
    #expect(!LocalMediaPath.isLocal(remote: "192.168.1.25", local: "192.168.1.10",
                                    remoteType: "relay", localType: "host", interfaces: interfaces))
    #expect(!LocalMediaPath.isLocal(remote: "192.168.1.25", local: "192.168.1.10",
                                    remoteType: "host", localType: "srflx", interfaces: interfaces))
    #expect(!LocalMediaPath.isLocal(remote: "192.168.1.25", local: "192.168.1.10",
                                    remoteType: "host", localType: "host", interfaces: []))
}

@Test func rumbleParsesBoundsMetadataAndClamps() {
    let plain = Data([0x80, 0, 0, 0, 70, 40, 20, 10, 0xf4, 0x01, 0x64, 0, 2])
    let command = RumbleCommand.parse(plain)
    #expect(command?.strong == 0.7)
    #expect(command?.weak == 0.4)
    #expect(command?.duration == 0.5)
    #expect(command?.delay == 0.1)
    #expect(command?.repeatCount == 2)
    #expect(RumbleCommand.parse(Data(plain.dropLast())) == nil)
    #expect(RumbleCommand.parse(Data([0, 0])) == nil)
    #expect(RumbleCommand.parse(Data([0x80, 0, 1] + Array(plain.dropFirst(3)))) == nil)
    let metadata = Data([0x90, 0] + Array(repeating: 0, count: 8) + Array(plain.dropFirst(2)))
    #expect(RumbleCommand.parse(metadata) == command)
    let loud = Data([0x80, 0, 0, 0, 255, 255, 255, 255, 0xff, 0xff, 0xff, 0xff, 255])
    #expect(RumbleCommand.parse(loud)?.strong == 1)
    #expect(RumbleCommand.parse(loud)?.duration == 2)
    #expect(RumbleCommand.parse(loud)?.repeatCount == 3)
}

@Test func homeConsoleParserSeparatesPowerFromPresence() throws {
    let data = Data(#"{"results":[{"serverId":"live-id","deviceName":"Living Room","consoleType":"XboxSeriesX","powerState":"On"}]}"#.utf8)
    let console = try #require(HomeService.parse(data, key: "results", streamable: true).first)
    #expect(console.name == "Living Room")
    #expect(console.powerState == "On")
    #expect(!console.local)
    #expect(console.inHomeService)
    #expect(!console.standby)
    #expect(HomeConsole(id: "id", name: "Xbox", model: "Xbox", powerState: "ConnectedStandby").standby)
    #expect(ConsoleDiscovery.parse(Data([0xdd, 0x01])) == nil)
}

@Test func discoveryResponseUsesCertificateLiveID() throws {
    let certificate = try #require(Data(base64Encoded: "MIIBgzCCASmgAwIBAgIUL88qD9eaGrJlmbuMWJbmsWycQVgwCgYIKoZIzj0EAwIwFzEVMBMGA1UEAwwMVEVTVC1MSVZFLUlEMB4XDTI2MDkyMzAyMTY1NFoXDTI2MDkyNDAyMTY1NFowFzEVMBMGA1UEAwwMVEVTVC1MSVZFLUlEMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEb+YPs9JcIXFBLN0vaNJfFV/bQ+o4kDfNyYrtQkiY7WWEqQoy15LO7eaDDegEWeCYBIYHfItSoCeYpoqDJmrXCaNTMFEwHQYDVR0OBBYEFBMfe7iGAZEZTJx58enMRD596GoEMB8GA1UdIwQYMBaAFBMfe7iGAZEZTJx58enMRD596GoEMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIgInGsVXaDeHjtc3I6HDGbqkZRopweXz6tJDftKR8ZCyYCIQDVDJ5/MXm6BjdKxogYLnqCm9chdphPaq798M4UX4RFpA=="))
    var payload = Data([0, 0, 0, 3, 0, 1, 0, 0])
    func appendString(_ value: String) {
        let utf8 = Array(value.utf8)
        payload.append(contentsOf: [UInt8(utf8.count >> 8), UInt8(utf8.count & 255)])
        payload.append(contentsOf: utf8)
        payload.append(0)
    }
    appendString("Living Room")
    appendString("00000000-0000-0000-0000-000000000001")
    payload.append(contentsOf: [0, 0, 0, 0])
    payload.append(contentsOf: [UInt8(certificate.count >> 8), UInt8(certificate.count & 255)])
    payload.append(certificate)
    let length = payload.count
    let packet = Data([0xdd, 0x01, UInt8(length >> 8), UInt8(length & 255), 0, 0]) + payload
    let found = try #require(ConsoleDiscovery.parse(packet))
    #expect(found.name == "Living Room")
    #expect(found.liveID == "TEST-LIVE-ID")
    #expect(ConsoleDiscovery.parse(Data(packet.dropLast())) == nil)
}

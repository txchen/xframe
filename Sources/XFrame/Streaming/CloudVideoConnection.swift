import Foundation
import QuartzCore
@preconcurrency import WebRTC

enum StreamError: Error, LocalizedError {
    case signaling, connection, firstFrame, stalled, decoder(String)
    var errorDescription: String? {
        switch self {
        case .signaling: "WebRTC negotiation failed."
        case .connection: "The WebRTC connection failed or was closed."
        case .firstFrame: "No hardware-decoded video frame arrived within 45 seconds."
        case .stalled: "Cloud video stopped receiving frames."
        case .decoder(let reason): "Video pipeline failure: " + reason
        }
    }
}

@MainActor
final class CloudVideoConnection {
    let video = LiveVideo()
    private var factory: RTCPeerConnectionFactory?
    private var peer: RTCPeerConnection?
    private var events: PeerEvents?
    private var channels: [String: RTCDataChannel] = [:]
    private var videoTrack: RTCVideoTrack?
    private var candidates: [CloudICECandidate] = []
    private var gatheringComplete = false
    private var connectionFailed = false
    private var handshakeReady = false
    private var controlStarted = false
    private var inputStarted = false
    private var closed = false
    private var messageCounter = 0
    private var samplingStats = false
    private let correlationID = UUID().uuidString.replacingOccurrences(of: "-", with: "")

    func run(service: any CloudSignaling, session: URL, report: (String) -> Void) async throws {
        defer { close() }
        RTCSetMinDebugLogLevel(.none)
        let factory = RTCPeerConnectionFactory(encoderFactory: RTCVideoEncoderFactoryH264(),
                                                decoderFactory: HardwareH264Factory(output: video))
        self.factory = factory
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
        config.iceServers = [RTCIceServer(urlStrings: ["stun:worldaz.relay.teams.microsoft.com:3478"])]
        let events = PeerEvents(owner: self)
        self.events = events
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = factory.peerConnection(with: config, constraints: constraints, delegate: events) else { throw StreamError.signaling }
        self.peer = peer
        for (name, wireProtocol) in [("input", "1.0"), ("chat", "chatV1"), ("control", "controlV1"), ("message", "messageV1")] {
            let settings = RTCDataChannelConfiguration()
            settings.isOrdered = true
            settings.protocol = wireProtocol
            guard let channel = peer.dataChannel(forLabel: name, configuration: settings) else { throw StreamError.signaling }
            channel.delegate = events
            channels[name] = channel
        }
        let receive = RTCRtpTransceiverInit()
        receive.direction = .recvOnly
        guard peer.addTransceiver(of: .video, init: receive) != nil else { throw StreamError.signaling }
        // xCloud expects an audio media section, but no local microphone track is
        // created. Disable the receiver track before applying the remote SDP.
        if let audio = peer.addTransceiver(of: .audio, init: receive) { audio.receiver.track?.isEnabled = false }
        report("Negotiating H.264 video…")
        let offer = try await makeOffer(peer)
        try await setDescription(peer, sdp: offer, local: true)
        let answer = try await service.exchangeSDP(at: session, offer: offer)
        try Task.checkCancellation()
        try await setDescription(peer, sdp: answer, local: false)
        let gatherDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !gatheringComplete && ContinuousClock.now < gatherDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard !candidates.isEmpty else { throw StreamError.connection }
        report("Connecting encrypted video transport…")
        let remote = try await service.exchangeICE(at: session, candidates: candidates)
        for candidate in remote {
            if candidate.candidate.contains("end-of-candidates") { continue }
            let raw = candidate.candidate.hasPrefix("a=") ? String(candidate.candidate.dropFirst(2)) : candidate.candidate
            let ice = RTCIceCandidate(sdp: raw, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                peer.add(ice) { error in
                    if error != nil { continuation.resume(throwing: StreamError.signaling) }
                    else { continuation.resume() }
                }
            }
        }
        let keepAliveInterval = try await service.keepAliveInterval(at: session)
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        var nextKeepAlive = ContinuousClock.now
        var nextKeyframeRequest = ContinuousClock.now
        var nextStatsSample = ContinuousClock.now
        while true {
            try Task.checkCancellation()
            guard !connectionFailed else { throw StreamError.connection }
            let stats = video.snapshot()
            if ContinuousClock.now >= nextStatsSample {
                sampleNetworkStats(peer)
                nextStatsSample = ContinuousClock.now.advanced(by: .seconds(2))
            }
            if stats.state.hasPrefix("Failed:") { throw StreamError.decoder(stats.state) }
            if stats.decoded > 0 { report("Streaming H.264 video — audio and input disabled") }
            else if ContinuousClock.now > deadline { throw StreamError.firstFrame }
            if let age = video.secondsSinceFrame, age > 15 { throw StreamError.stalled }
            if ContinuousClock.now >= nextKeyframeRequest, channels["control"]?.readyState == .open,
               video.takeKeyframeRequest() {
                send(["message": "videoKeyframeRequested", "ifrRequested": true], on: "control")
                nextKeyframeRequest = ContinuousClock.now.advanced(by: .seconds(1))
            }
            if ContinuousClock.now >= nextKeepAlive {
                try await service.keepAlive(at: session)
                nextKeepAlive = ContinuousClock.now.advanced(by: .seconds(keepAliveInterval))
            }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private func sampleNetworkStats(_ peer: RTCPeerConnection) {
        guard !samplingStats, !closed else { return }
        samplingStats = true
        let video = self.video
        // Completion-style sampling does not block keepalive or stall checks.
        // Whitelist numeric fields; whole reports can contain network addresses.
        peer.statistics { [weak self] report in
            if let inbound = report.statistics.values.first(where: {
                $0.type == "inbound-rtp" && ($0.values["kind"] as? String) == "video"
            }) {
                video.networkSample(received: (inbound.values["packetsReceived"] as? NSNumber)?.intValue,
                    lost: (inbound.values["packetsLost"] as? NSNumber)?.intValue,
                    nacks: (inbound.values["nackCount"] as? NSNumber)?.intValue)
            }
            Task { @MainActor [weak self] in self?.samplingStats = false }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        if let videoTrack { videoTrack.remove(video) }
        videoTrack = nil
        for channel in channels.values { channel.delegate = nil; channel.close() }
        channels.removeAll()
        peer?.delegate = nil
        peer?.close()
        peer = nil; events = nil; factory = nil
        video.stop()
    }

    private func makeOffer(_ peer: RTCPeerConnection) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            peer.offer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { sdp, error in
                guard error == nil, let sdp else { continuation.resume(throwing: StreamError.signaling); return }
                continuation.resume(returning: sdp.sdp)
            }
        }
    }
    private func setDescription(_ peer: RTCPeerConnection, sdp: String, local: Bool) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let description = RTCSessionDescription(type: local ? .offer : .answer, sdp: sdp)
            let completion: @Sendable (Error?) -> Void = { error in
                if error != nil { continuation.resume(throwing: StreamError.signaling) } else { continuation.resume() }
            }
            if local { peer.setLocalDescription(description, completionHandler: completion) }
            else { peer.setRemoteDescription(description, completionHandler: completion) }
        }
    }
    fileprivate func generated(_ candidate: CloudICECandidate) { if !closed { candidates.append(candidate) } }
    fileprivate func gathered() { gatheringComplete = true }
    fileprivate func failed() { connectionFailed = true }
    fileprivate func received(_ track: RTCMediaStreamTrack?) {
        guard !closed else { return }
        if let track = track as? RTCVideoTrack {
            videoTrack?.remove(video)
            videoTrack = track
            track.add(video)
        } else { track?.isEnabled = false }
    }
    fileprivate func channelOpened(_ name: String) {
        guard !closed else { return }
        if name == "message" { send(["type": "Handshake", "version": "messageV1", "id": UUID().uuidString, "cv": nextCV()], on: name) }
        startControlIfReady()
    }
    fileprivate func message(_ data: Data, on name: String) {
        guard !closed, name == "message", data.count < 65536,
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if message["type"] as? String == "HandshakeAck", message["version"] as? String == "messageV1", !handshakeReady {
            handshakeReady = true
            startControlIfReady()
            sendMessage("/streaming/systemUi/configuration", content: ["version": [0, 2, 0], "systemUis": [Int]()])
            sendMessage("/streaming/properties/clientappinstallidchanged", content: ["clientAppInstallId": UUID().uuidString])
            sendMessage("/streaming/characteristics/orientationchanged", content: ["orientation": 0])
            sendMessage("/streaming/characteristics/touchinputenabledchanged", content: ["touchInputEnabled": false])
            sendMessage("/streaming/characteristics/clientdevicecapabilities", content: [:])
            sendMessage("/streaming/characteristics/dimensionschanged", content: ["horizontal": 1920, "vertical": 1080,
                "preferredWidth": 1920, "preferredHeight": 1080, "safeAreaLeft": 0, "safeAreaTop": 0,
                "safeAreaRight": 1920, "safeAreaBottom": 1080, "supportsCustomResolution": true])
        } else if message["type"] as? String == "TransactionStart", let id = message["id"] as? String,
                  let target = message["target"] as? String {
            send(["type": "Unhandled", "id": id, "target": target, "cv": nextCV()], on: "message")
        }
    }
    private func startControlIfReady() {
        guard handshakeReady else { return }
        if !controlStarted, channels["control"]?.readyState == .open {
            controlStarted = true
            // Fixed protocol access key from the reference, not an account secret.
            send(["message": "authorizationRequest", "accessKey": "4BDB3609-C1F1-4195-9B37-FEFF45DA8B8E"], on: "control")
            send(["message": "videoKeyframeRequested", "ifrRequested": false], on: "control")
        }
        if !inputStarted, let input = channels["input"], input.readyState == .open {
            inputStarted = true
            var metadata = Data([8, 0, 0, 0, 0, 0])
            var time = (CACurrentMediaTime() * 1000).bitPattern.littleEndian
            withUnsafeBytes(of: &time) { metadata.append(contentsOf: $0) }
            metadata.append(0) // No touch points; no gamepad or key reports are sent.
            _ = input.sendData(RTCDataBuffer(data: metadata, isBinary: true))
        }
    }
    private func nextCV() -> String { messageCounter += 1; return "\(correlationID).\(messageCounter)" }
    private func sendMessage(_ target: String, content: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: content) else { return }
        send(["type": "Message", "id": UUID().uuidString, "target": target,
              "content": String(decoding: body, as: UTF8.self), "cv": nextCV()], on: "message")
    }
    private func send(_ message: [String: Any], on name: String) {
        guard let channel = channels[name], channel.readyState == .open,
              let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        _ = channel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }
}

// WebRTC invokes delegates on its signaling thread. Hop only control events to
// the main actor; video frames go directly into the lock-protected latest slot.
private final class PeerEvents: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, @unchecked Sendable {
    private weak var owner: CloudVideoConnection?
    init(owner: CloudVideoConnection) { self.owner = owner }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        if newState == .failed || newState == .closed { Task { @MainActor [weak owner] in owner?.failed() } }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState == .complete { Task { @MainActor [weak owner] in owner?.gathered() } }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let value = CloudICECandidate(candidate: candidate.sdp, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex)
        Task { @MainActor [weak owner] in owner?.generated(value) }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        let track = rtpReceiver.track
        Task { @MainActor [weak owner] in owner?.received(track) }
    }
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        if dataChannel.readyState == .open {
            let label = dataChannel.label
            Task { @MainActor [weak owner] in owner?.channelOpened(label) }
        }
    }
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let label = dataChannel.label
        let data = buffer.data
        Task { @MainActor [weak owner] in owner?.message(data, on: label) }
    }
}

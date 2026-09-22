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
    let video: LiveVideo
    init(framePacing: FramePacingMode = .balanced) {
        video = LiveVideo(framePacing: framePacing)
    }
    private let audio = CloudAudioPlayback()

    func configureAudio(muted: Bool, volume: Double) {
        audio.configure(muted: muted, volume: volume)
        video.audioPlayback(attached: audio.hasTrack, muted: audio.muted, volume: audio.volume)
    }
    var controllerEnabled = false { didSet { updateControllerCapture(); if !controllerEnabled { input.release(); hudShortcut.reset() } } }
    var playbackFocused = false { didSet { updateControllerCapture(); if !playbackFocused { input.release(); hudShortcut.reset() } } }
    private func updateControllerCapture() {
        gamepad.capturesSystemGestures = controllerEnabled && playbackFocused
    }
    private let gamepad = NativeGamepad()
    private var input = GamepadInput()
    private var hudShortcut = GamepadHUDShortcut()
    var cyclePerformanceOverlay: (() -> Void)?
    private var inputTask: Task<Void, Never>?
    private var gamepadReset = false
    private var advertised = false
    private var addAfter = 0.0
    private var blockedSince: Double?
    private(set) var controllerStatus = "Controller input off"
    private var ownsController: Bool {
        controllerEnabled && playbackFocused && gamepad.connected && advertised && !closed
    }

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
        gamepad.changed = { [weak self] state in
            guard let self else { return }
            self.processGamepad(state)
        }
        gamepad.replaced = { [weak self] in self?.input.release(); self?.hudShortcut.reset() }
        inputTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tickInput()
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
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
        // Receive game audio without a microphone/capture track or send direction.
        guard let audioReceiver = peer.addTransceiver(of: .audio, init: receive) else { throw StreamError.signaling }
        received(audioReceiver.receiver.track)
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
        var reportedStreaming = false
        while true {
            try Task.checkCancellation()
            guard !connectionFailed else { throw StreamError.connection }
            let stats = video.streamState
            if ContinuousClock.now >= nextStatsSample {
                sampleNetworkStats(peer)
                nextStatsSample = ContinuousClock.now.advanced(by: .seconds(1))
            }
            if stats.state.hasPrefix("Failed:") { throw StreamError.decoder(stats.state) }
            if stats.hasFrames {
                if !reportedStreaming {
                    report("Streaming H.264 video and game audio")
                    reportedStreaming = true
                }
            }
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
                let transportID = inbound.values["transportId"] as? String
                let transport = transportID.flatMap { report.statistics[$0] }
                let pairID = transport?.values["selectedCandidatePairId"] as? String
                let pair = pairID.flatMap { report.statistics[$0] }
                let roundTrip = (pair?.values["currentRoundTripTime"] as? NSNumber)?.doubleValue
                video.networkSample(received: (inbound.values["packetsReceived"] as? NSNumber)?.intValue,
                    lost: (inbound.values["packetsLost"] as? NSNumber)?.intValue,
                    nacks: (inbound.values["nackCount"] as? NSNumber)?.intValue,
                    bytes: (inbound.values["bytesReceived"] as? NSNumber)?.doubleValue,
                    timestampUS: inbound.timestamp_us, streamID: inbound.id,
                    roundTripSeconds: roundTrip,
                    jitterBufferDelay: (inbound.values["jitterBufferDelay"] as? NSNumber)?.doubleValue,
                    jitterBufferEmittedCount: (inbound.values["jitterBufferEmittedCount"] as? NSNumber)?.doubleValue)
            } else {
                video.networkSample(received: nil, lost: nil, nacks: nil)
            }
            if let inbound = report.statistics.values.first(where: {
                $0.type == "inbound-rtp" && ($0.values["kind"] as? String) == "audio"
            }) {
                video.audioNetworkSample(received: (inbound.values["packetsReceived"] as? NSNumber)?.intValue,
                    energy: (inbound.values["totalAudioEnergy"] as? NSNumber)?.doubleValue)
            }
            Task { @MainActor [weak self] in self?.samplingStats = false }
        }
    }

    func close() {
        guard !closed else { return }
        inputTask?.cancel()
        inputTask = nil
        input.release()
        if advertised {
            _ = input.send(timestampMS: CACurrentMediaTime() * 1000) { [self] data in
                channels["input"]?.sendData(RTCDataBuffer(data: data, isBinary: true)) ?? false
            }
            _ = send(["message": "gamepadChanged", "gamepadIndex": 0, "wasAdded": false], on: "control")
        }
        gamepad.stop()
        closed = true
        audio.stop()
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
    fileprivate func channelClosed(_ name: String) {
        if !closed && ["input", "control", "message"].contains(name) { connectionFailed = true }
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
        } else if let track = track as? RTCAudioTrack {
            audio.attach(WebRTCAudioOutput(track: track))
            video.audioPlayback(attached: audio.hasTrack, muted: audio.muted, volume: audio.volume)
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
            // Fixed protocol access key from the reference, not an account secret.
            controlStarted = send(["message": "authorizationRequest", "accessKey": "4BDB3609-C1F1-4195-9B37-FEFF45DA8B8E"], on: "control")
            send(["message": "videoKeyframeRequested", "ifrRequested": false], on: "control")
        }
        if !inputStarted, let input = channels["input"], input.readyState == .open {
            var metadata = Data([8, 0, 0, 0, 0, 0])
            var time = (CACurrentMediaTime() * 1000).bitPattern.littleEndian
            withUnsafeBytes(of: &time) { metadata.append(contentsOf: $0) }
            metadata.append(0) // No touch points.
            inputStarted = input.sendData(RTCDataBuffer(data: metadata, isBinary: true))
        }
    }
    private func tickInput() {
        guard !closed else { return }
        gamepad.refresh()
        startControlIfReady()
        let now = CACurrentMediaTime()
        guard handshakeReady && controlStarted && inputStarted,
              let channel = channels["input"], channel.readyState == .open,
              channels["control"]?.readyState == .open else {
            input.release()
            controllerStatus = controllerEnabled ? "Controller waiting for transport" : "Controller input off"
            return
        }
        if !gamepadReset {
            guard send(["message": "gamepadChanged", "gamepadIndex": 0, "wasAdded": false], on: "control") else { return }
            gamepadReset = true
            addAfter = now + 0.5
        }
        let wanted = controllerEnabled && gamepad.connected
        if advertised && !wanted {
            input.release()
            guard sendInput(on: channel, now: now) else { return }
            guard send(["message": "gamepadChanged", "gamepadIndex": 0, "wasAdded": false], on: "control") else { return }
            advertised = false
            addAfter = now + 0.5
        }
        if wanted && !advertised && now >= addAfter {
            guard send(["message": "gamepadChanged", "gamepadIndex": 0, "wasAdded": true], on: "control") else { return }
            advertised = true
            input.release()
        }
        processGamepad(gamepad.sample())
        if advertised { _ = sendInput(on: channel, now: now) }
        let name = gamepad.name ?? "Gamepad"
        if !controllerEnabled { controllerStatus = "Controller input off (View menu)" }
        else if !gamepad.connected { controllerStatus = "Connect a controller" }
        else if !playbackFocused { controllerStatus = "\(name) · paused (focus playback)" }
        else if !advertised { controllerStatus = "\(name) · connecting" }
        else if blockedSince != nil { controllerStatus = "\(name) · input transport blocked" }
        else if !input.armed { controllerStatus = "\(name) · release all controls" }
        else { controllerStatus = "\(name) · input active · sent \(input.encoder.sequence)" }
    }

    private func processGamepad(_ state: GamepadSnapshot) {
        guard ownsController, input.armed else {
            hudShortcut.reset()
            input.update(state, ownsInput: ownsController)
            return
        }
        let result = hudShortcut.process(state, now: CACurrentMediaTime())
        for state in result.states { input.update(state, ownsInput: true) }
        if result.cycle { cyclePerformanceOverlay?() }
    }

    private func sendInput(on channel: RTCDataChannel, now: Double) -> Bool {
        // Keep WebRTC's queue small too, so stale held states cannot accumulate indefinitely.
        let accepted = input.send(timestampMS: now * 1000) { data in
            channel.bufferedAmount < 4096 && channel.sendData(RTCDataBuffer(data: data, isBinary: true))
        }
        if accepted { blockedSince = nil }
        else {
            if blockedSince == nil { blockedSince = now }
            if now - (blockedSince ?? now) > 2 { connectionFailed = true }
        }
        return accepted
    }

    private func nextCV() -> String { messageCounter += 1; return "\(correlationID).\(messageCounter)" }
    private func sendMessage(_ target: String, content: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: content) else { return }
        send(["type": "Message", "id": UUID().uuidString, "target": target,
              "content": String(decoding: body, as: UTF8.self), "cv": nextCV()], on: "message")
    }
    @discardableResult
    private func send(_ message: [String: Any], on name: String) -> Bool {
        guard let channel = channels[name], channel.readyState == .open,
              channel.bufferedAmount < 4096,
              let data = try? JSONSerialization.data(withJSONObject: message) else { return false }
        return channel.sendData(RTCDataBuffer(data: data, isBinary: false))
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
        if dataChannel.readyState == .closed || dataChannel.readyState == .closing {
            let label = dataChannel.label
            Task { @MainActor [weak owner] in owner?.channelClosed(label) }
        }
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

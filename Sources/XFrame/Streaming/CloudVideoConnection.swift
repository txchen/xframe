import Foundation
import QuartzCore
@preconcurrency import WebRTC

enum StreamError: Error, LocalizedError {
    case signaling, connection, firstFrame, stalled, heartbeat, localPath, decoder(String)
    var errorDescription: String? {
        switch self {
        case .signaling: "WebRTC negotiation failed."
        case .connection: "The WebRTC connection failed or was closed."
        case .firstFrame: "No hardware-decoded video frame arrived within 45 seconds."
        case .heartbeat: "The streaming session heartbeat failed. End the session and retry."
        case .stalled: "Stream video stopped receiving frames."
        case .localPath: "A direct local network path to this Xbox could not be verified. The session was stopped."
        case .decoder(let reason): "Video pipeline failure: " + reason
        }
    }
    var diagnosticKind: StreamDiagnosticEvent.Kind {
        switch self {
        case .signaling: .startupFailed
        case .connection: .transportFailed
        case .firstFrame: .firstFrameTimeout
        case .stalled: .videoStalled
        case .heartbeat: .heartbeatFailed
        case .localPath: .transportFailed
        case .decoder: .decoderFailed
        }
    }
}

@MainActor
final class CloudVideoConnection {
    let video: LiveVideo
    init(framePacing: FramePacingMode = .balanced, requireLocalMedia: Bool = false) {
        video = LiveVideo(framePacing: framePacing)
        self.requireLocalMedia = requireLocalMedia
    }
    private let requireLocalMedia: Bool
    private var localPathVerified = false
    private var localPathRejected = false
    private var connectedAt: Double?
    private var localVideoPresented = false
    var localPathChanged: ((Bool) -> Void)?
    private let audio = CloudAudioPlayback()
    private var requestedMuted = false
    private var requestedVolume = 1.0

    func configureAudio(muted: Bool, volume: Double) {
        requestedMuted = muted
        requestedVolume = volume
        audio.configure(muted: muted || (requireLocalMedia && !localPathVerified), volume: volume)
        video.audioPlayback(attached: audio.hasTrack, muted: audio.muted, volume: audio.volume)
    }
    var controllerEnabled = false { didSet { updateControllerCapture(); releaseInput(); if !controllerEnabled { gamepad.stopRumble() } } }
    var keyboardEnabled = false { didSet { updateControllerCapture(); releaseInput() } }
    var playbackFocused = false { didSet { updateControllerCapture(); if !playbackFocused { releaseInput(); gamepad.stopRumble() } } }
    private var keyboard = KeyboardGamepad()
    private var ownership = InputOwnership()
    private var inputEnabled: Bool { keyboardEnabled || controllerEnabled }
    private var inputConnected: Bool { keyboardEnabled || (controllerEnabled && gamepad.connected) }
    private func releaseInput() {
        keyboard.release(); input.release(); settingsShortcut.reset()
        ownership.reset(controller: gamepad.sample())
    }
    private func handoffInput() {
        keyboard.release(); input.release(); settingsShortcut.reset()
        input.update(GamepadSnapshot(), ownsInput: ownsController)
    }
    private func controllerEvent(_ state: GamepadSnapshot) {
        if playbackSettingsVisible {
            input.update(GamepadSnapshot(), ownsInput: false)
            if controllerEnabled && playbackFocused && !closed { settingsGamepad?(state) }
            return
        }
        if ownership.observeController(state, enabled: controllerEnabled && ownsController) { handoffInput() }
        if ownership.active == .controller || (!keyboardEnabled && controllerEnabled) { processGamepad(state) }
    }
    @discardableResult
    func keyboardEvent(code: UInt16, down: Bool, repeatKey: Bool, shortcut: Bool) -> Bool {
        guard keyboardEnabled && playbackFocused && !closed else { return false }
        if shortcut { releaseKeyboard(); return false }
        // Validate the key before it can take ownership. Repeats and key-up never claim.
        var probe = keyboard
        let handled = probe.handle(code: code, down: down, repeatKey: repeatKey)
        guard handled else { return false }
        if down && !repeatKey && ownsController && ownership.claimKeyboard() { handoffInput() }
        if ownership.active == .keyboard {
            keyboard.handle(code: code, down: down, repeatKey: repeatKey)
            processGamepad(keyboard.snapshot)
        }
        return true
    }
    func releaseKeyboard() { if ownership.active == .keyboard { releaseInput() } }
    private func updateControllerCapture() {
        gamepad.capturesSystemGestures = controllerEnabled && playbackFocused
    }
    private let gamepad = NativeGamepad()
    private var input = GamepadInput()
    private var settingsShortcut = GamepadSettingsShortcut()
    var showPlaybackSettings: (() -> Void)?
    var settingsGamepad: ((GamepadSnapshot) -> Void)?
    var playbackSettingsVisible = false { didSet { releaseInput(); if playbackSettingsVisible { gamepad.stopRumble() } } }
    private var inputTask: Task<Void, Never>?
    private var gamepadReset = false
    private var advertised = false
    private var addAfter = 0.0
    private var blockedSince: Double?
    private(set) var controllerStatus = "Controller input off"
    var rumbleStatus: String { gamepad.rumbleStatus }
    private var ownsController: Bool {
        inputEnabled && playbackFocused && inputConnected && advertised && !closed && !recovering && health.disconnectedAt == nil && blockedSince == nil && (!requireLocalMedia || localPathVerified)
    }

    private var factory: RTCPeerConnectionFactory?
    private var peer: RTCPeerConnection?
    private var events: PeerEvents?
    private var channels: [String: RTCDataChannel] = [:]
    private var videoTrack: RTCVideoTrack?
    private var candidates: [CloudICECandidate] = []
    private var gatheringComplete = false
    private var connectionFailed = false
    private var health = StreamHealth()
    private var recovering = false
    private let heartbeat = StreamHeartbeat()
    private var handshakeReady = false
    private var handshakeSent = false
    private var controlStarted = false
    private var inputStarted = false
    private var closed = false
    private var messageCounter = 0
    private var samplingStats = false
    private let correlationID = UUID().uuidString.replacingOccurrences(of: "-", with: "")

    func run(service: any CloudSignaling, session: URL, report: (String) -> Void) async throws {
        try await withLifecycle {
            try await runSession(service: service, session: session, report: report)
        }
    }

    // Keep failure recording ahead of teardown, including failures before first output.
    func withLifecycle(_ operation: () async throws -> Void) async throws {
        defer { close() }
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        do { try await operation() }
        catch {
            if !Task.isCancelled && !(error is CancellationError) && !closed {
                video.fail((error as? LocalizedError)?.errorDescription ?? "Stream failed",
                           kind: (error as? StreamError)?.diagnosticKind ?? .startupFailed)
            }
            throw error
        }
    }

    private func checkActive() throws {
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
    }

    private func runSession(service: any CloudSignaling, session: URL, report: (String) -> Void) async throws {
        gamepad.changed = { [weak self] state in
            guard let self else { return }
            self.controllerEvent(state)
        }
        gamepad.replaced = { [weak self] in
            guard let self else { return }
            if self.ownership.active == .keyboard {
                self.ownership.reset(controller: self.gamepad.sample())
                _ = self.ownership.claimKeyboard()
                return
            }
            self.releaseInput()
        }
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
        try checkActive()
        try await setDescription(peer, sdp: offer, local: true)
        try checkActive()
        let answer = try await service.exchangeSDP(at: session, offer: offer)
        try checkActive()
        try await setDescription(peer, sdp: answer, local: false)
        let gatherDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !gatheringComplete && ContinuousClock.now < gatherDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try checkActive()
        guard !candidates.isEmpty else { throw StreamError.connection }
        report("Connecting encrypted video transport…")
        let remote = try await service.exchangeICE(at: session, candidates: candidates)
        try checkActive()
        for candidate in remote {
            try checkActive()
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
        try checkActive()
        let keepAliveInterval = try await service.keepAliveInterval(at: session)
        try checkActive()
        heartbeat.start(interval: keepAliveInterval, pulse: { try await service.keepAlive(at: session) }) { [weak self] kind in
            self?.video.connectionEvent(kind)
        }
        let startedAt = CACurrentMediaTime()
        var nextStatsSample = ContinuousClock.now
        var reportedStreaming = false
        while true {
            try checkActive()
            guard heartbeat.failure == nil else { throw StreamError.heartbeat }
            guard !connectionFailed else { throw StreamError.connection }
            if requireLocalMedia {
                if localPathRejected { throw StreamError.localPath }
                if let connectedAt, !localPathVerified, CACurrentMediaTime() - connectedAt > 6 { throw StreamError.localPath }
            }
            let stats = video.streamState
            if ContinuousClock.now >= nextStatsSample {
                sampleNetworkStats(peer)
                nextStatsSample = ContinuousClock.now.advanced(by: .seconds(1))
            }
            if stats.state.hasPrefix("Failed:") { throw StreamError.decoder(stats.state) }
            let now = CACurrentMediaTime()
            let action = health.action(now: now, startedAt: startedAt, frameAge: video.secondsSinceFrame, inputBlockedAt: blockedSince)
            switch action {
            case .transportFailed: throw StreamError.connection
            case .firstFrameTimeout: throw StreamError.firstFrame
            case .stalled: throw StreamError.stalled
            case .recovering:
                if !recovering {
                    recovering = true
                    video.setRecovering(true)
                    releaseInput()
                    video.connectionEvent(.recoveryStarted)
                    report("Connection interrupted — recovering…")
                }
            case .playing:
                if requireLocalMedia && !localPathVerified { break }
                if recovering {
                    recovering = false
                    video.setRecovering(false)
                    video.connectionEvent(.recoveryCompleted)
                }
                if !reportedStreaming {
                    reportedStreaming = true
                    report("Streaming H.264 video and game audio")
                }
            case .waiting: break
            }
            if recovering { reportedStreaming = false }
            // Retain a pending decoder request until the channel can send it.
            if channels["control"]?.readyState == .open {
                if health.shouldRequestKeyframe(now: now, recovering: recovering, decoderRequested: video.hasKeyframeRequest) {
                    _ = video.takeKeyframeRequest()
                    if !send(["message": "videoKeyframeRequested", "ifrRequested": true], on: "control") {
                        video.requestKeyframe()
                    }
                }
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
            let transport = report.statistics.values.first(where: { $0.type == "transport" && $0.values["selectedCandidatePairId"] != nil })
            let selectedPair = (transport?.values["selectedCandidatePairId"] as? String).flatMap { report.statistics[$0] }
            let localCandidate = (selectedPair?.values["localCandidateId"] as? String).flatMap { report.statistics[$0] }
            let remoteCandidate = (selectedPair?.values["remoteCandidateId"] as? String).flatMap { report.statistics[$0] }
            let path: (String, String, String, String)? = {
                guard let local = localCandidate, let remote = remoteCandidate,
                      let localAddress = (local.values["address"] ?? local.values["ip"]) as? String,
                      let remoteAddress = (remote.values["address"] ?? remote.values["ip"]) as? String,
                      let localType = local.values["candidateType"] as? String,
                      let remoteType = remote.values["candidateType"] as? String else { return nil }
                return (remoteAddress, localAddress, remoteType, localType)
            }()
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
            Task { @MainActor [weak self] in
                guard let self, !self.closed else { return }
                self.samplingStats = false
                if self.requireLocalMedia, let path {
                    let valid = LocalMediaPath.isLocal(remote: path.0, local: path.1,
                        remoteType: path.2, localType: path.3, interfaces: LocalMediaPath.interfaces())
                    let wasVerified = self.localPathVerified
                    self.localPathVerified = valid
                    self.localPathRejected = !valid
                    if !valid { self.releaseInput(); self.gamepad.stopRumble() }
                    if wasVerified != valid {
                        self.configureAudio(muted: self.requestedMuted, volume: self.requestedVolume)
                        if valid && !self.localVideoPresented {
                            self.localVideoPresented = true
                            self.localPathChanged?(true)
                        } else if !valid { self.localPathChanged?(false) }
                    }
                }
            }
        }
    }

    func close() {
        guard !closed else { return }
        heartbeat.stop()
        inputTask?.cancel()
        inputTask = nil
        releaseInput()
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
        if !closed && ["input", "control", "message"].contains(name) {
            video.connectionEvent(.dataChannelClosed)
            connectionFailed = true
        }
    }
    fileprivate func generated(_ candidate: CloudICECandidate) { if !closed { candidates.append(candidate) } }
    fileprivate func gathered() { gatheringComplete = true }
    fileprivate func transportChanged(_ state: StreamHealth.Transport) {
        guard !closed else { return }
        let wasDisconnected = health.disconnectedAt != nil
        health.updateTransport(state, now: CACurrentMediaTime())
        if requireLocalMedia {
            if state == .connected && (connectedAt == nil || wasDisconnected) {
                connectedAt = CACurrentMediaTime(); localPathVerified = false
            }
            if state == .disconnected || state == .failed {
                localPathVerified = false
                configureAudio(muted: requestedMuted, volume: requestedVolume)
                releaseInput()
                gamepad.stopRumble()
            }
        }
        if state == .failed { video.connectionEvent(.iceFailed) }
        if state == .disconnected && !wasDisconnected {
            releaseInput()
            video.connectionEvent(.transportDisconnected)
        } else if state == .connected && wasDisconnected {
            video.connectionEvent(.transportRecovered)
            video.requestKeyframe()
        }
    }
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
        startControlIfReady()
    }
    fileprivate func message(_ data: Data, on name: String) {
        guard !closed else { return }
        if name == "input" {
            if controllerEnabled && playbackFocused && (!requireLocalMedia || localPathVerified),
               let command = RumbleCommand.parse(data) { gamepad.vibrate(command) }
            return
        }
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
        guard !requireLocalMedia || localPathVerified else { return }
        if !handshakeSent && channels["message"]?.readyState == .open {
            handshakeSent = send(["type": "Handshake", "version": "messageV1", "id": UUID().uuidString, "cv": nextCV()], on: "message")
        }
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
        if requireLocalMedia && !localPathVerified {
            releaseInput()
            controllerStatus = "Waiting for verified local Xbox path"
            return
        }
        startControlIfReady()
        let now = CACurrentMediaTime()
        guard handshakeReady && controlStarted && inputStarted,
              let channel = channels["input"], channel.readyState == .open,
              channels["control"]?.readyState == .open else {
            input.release()
            controllerStatus = inputEnabled ? "Input waiting for transport" : "Game input off"
            return
        }
        if health.disconnectedAt != nil {
            releaseInput(); blockedSince = nil
            controllerStatus = "Controller paused — connection interrupted"
            return
        }
        if !gamepadReset {
            guard send(["message": "gamepadChanged", "gamepadIndex": 0, "wasAdded": false], on: "control") else { return }
            gamepadReset = true
            addAfter = now + 0.5
        }
        let wanted = inputEnabled && inputConnected
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
        controllerEvent(gamepad.sample())
        if ownership.active == .keyboard { processGamepad(keyboard.snapshot) }
        else if ownership.active == nil && keyboardEnabled { processGamepad(GamepadSnapshot()) }
        if advertised { _ = sendInput(on: channel, now: now) }
        let name = ownership.active == .keyboard ? "Keyboard" : ownership.active == .controller || !keyboardEnabled ? (gamepad.name ?? "Gamepad") : "Keyboard / Controller · awaiting input"
        if !inputEnabled { controllerStatus = "Game input off (View menu)" }
        else if !inputConnected { controllerStatus = "Connect a controller" }
        else if !playbackFocused { controllerStatus = "\(name) · paused (focus playback)" }
        else if !advertised { controllerStatus = "\(name) · connecting" }
        else if blockedSince != nil { controllerStatus = "\(name) · input transport blocked" }
        else if playbackSettingsVisible { controllerStatus = "Playback settings · game input paused" }
        else if !input.armed { controllerStatus = "\(name) · release all controls" }
        else { controllerStatus = "\(name) · input active · sent \(input.encoder.sequence)" }
    }

    private func processGamepad(_ state: GamepadSnapshot) {
        if playbackSettingsVisible {
            input.update(GamepadSnapshot(), ownsInput: false)
            return
        }
        guard ownsController, input.armed else {
            settingsShortcut.reset()
            input.update(state, ownsInput: ownsController)
            return
        }
        let result = settingsShortcut.process(state, now: CACurrentMediaTime())
        for state in result.states { input.update(state, ownsInput: true) }
        if result.openSettings { showPlaybackSettings?() }
    }

    private func sendInput(on channel: RTCDataChannel, now: Double) -> Bool {
        // Keep WebRTC's queue small too, so stale held states cannot accumulate indefinitely.
        let accepted = input.send(timestampMS: now * 1000, minimumButtonHoldMS: ownership.active == .keyboard ? 50 : 0) { data in
            channel.bufferedAmount < 4096 && channel.sendData(RTCDataBuffer(data: data, isBinary: true))
        }
        if accepted {
            if blockedSince != nil { video.connectionEvent(.inputSendRecovered) }
            blockedSince = nil
        } else if blockedSince == nil {
            blockedSince = now
            releaseInput()
            video.connectionEvent(.inputSendBlocked)
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
        let state: StreamHealth.Transport
        switch newState {
        case .connected, .completed: state = .connected
        case .disconnected: state = .disconnected
        case .failed, .closed: state = .failed
        default: state = .connecting
        }
        Task { @MainActor [weak owner] in owner?.transportChanged(state) }
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

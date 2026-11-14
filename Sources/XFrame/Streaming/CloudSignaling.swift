import Foundation

struct CloudICECandidate: Codable, Sendable {
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int32
    init(candidate: String, sdpMid: String?, sdpMLineIndex: Int32) {
        self.candidate = candidate; self.sdpMid = sdpMid; self.sdpMLineIndex = sdpMLineIndex
    }
    enum CodingKeys: String, CodingKey { case candidate, sdpMid, sdpMLineIndex }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        candidate = try values.decode(String.self, forKey: .candidate)
        sdpMid = try values.decodeIfPresent(String.self, forKey: .sdpMid)
        if let number = try? values.decode(Int32.self, forKey: .sdpMLineIndex) { sdpMLineIndex = number }
        else {
            let text = try values.decode(String.self, forKey: .sdpMLineIndex)
            guard let number = Int32(text) else { throw CloudError.response }
            sdpMLineIndex = number
        }
    }
}

protocol CloudSignaling: Sendable {
    func exchangeSDP(at: URL, offer: String) async throws -> String
    func exchangeICE(at: URL, candidates: [CloudICECandidate]) async throws -> [CloudICECandidate]
    func keepAlive(at: URL) async throws
    func keepAliveInterval(at: URL) async throws -> Double
}

extension CloudService: CloudSignaling {
    func exchangeSDP(at url: URL, offer: String) async throws -> String {
        let body: [String: Any] = ["messageType": "offer", "sdp": offer, "configuration": [
            "chatConfiguration": ["bytesPerSample": 2, "expectedClipDurationMs": 20,
                "format": ["codec": "opus", "container": "webm"], "numChannels": 1, "sampleFrequencyHz": 24000],
            "chat": ["minVersion": 1, "maxVersion": 1], "control": ["minVersion": 1, "maxVersion": 3],
            "input": ["minVersion": 1, "maxVersion": 8], "message": ["minVersion": 1, "maxVersion": 1]]]
        _ = try await request(url.appendingPathComponent("sdp"), method: "POST", body: JSONSerialization.data(withJSONObject: body))
        struct Answer: Decodable { let sdp: String }
        let result: Answer = try await exchangeResponse(at: url.appendingPathComponent("sdp"))
        guard !result.sdp.isEmpty else { throw CloudError.response }
        return result.sdp
    }
    func exchangeICE(at url: URL, candidates: [CloudICECandidate]) async throws -> [CloudICECandidate] {
        struct Request: Encodable { let messageType = "iceCandidate"; let candidate: [CloudICECandidate] }
        _ = try await request(url.appendingPathComponent("ice"), method: "POST",
            body: JSONEncoder().encode(Request(candidate: candidates)))
        return try await exchangeResponse(at: url.appendingPathComponent("ice"))
    }
    func keepAlive(at url: URL) async throws { _ = try await request(url.appendingPathComponent("keepalive"), method: "POST", body: Data("{}".utf8)) }
    func keepAliveInterval(at url: URL) async throws -> Double {
        struct Configuration: Decodable { let keepAlivePulseInSeconds: Double? }
        let data = try await request(url.appendingPathComponent("configuration"))
        let value = try JSONDecoder().decode(Configuration.self, from: data).keepAlivePulseInSeconds ?? 20
        return min(60, max(1, value))
    }
    private func exchangeResponse<T: Decodable>(at url: URL) async throws -> T {
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start + .seconds(30)
        while clock.now < deadline {
            try Task.checkCancellation()
            let data = try await request(url)
            try Task.checkCancellation()
            guard clock.now < deadline else { break }
            if let result: T = try SignalingResponse.decode(data) { return result }
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else { break }
            try await Task.sleep(for: min(SignalingPolling.delay(after: start.duration(to: clock.now)), remaining))
        }
        throw SignalingFailure.timedOut
    }
}

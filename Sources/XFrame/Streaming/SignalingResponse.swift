import Foundation

/// Expected host failures have actionable, fixed text; raw responses never reach the UI.
enum SignalingFailure: Error, LocalizedError {
    case consoleOffline, remotePlayDisabled, previousSessionClosing, duplicateSession, hostRejected, timedOut

    var errorDescription: String? {
        switch self {
        case .consoleOffline: "The console is not answering. Check that it is on and reachable."
        case .remotePlayDisabled: "Remote play is disabled on the console. Enable remote features in Xbox settings."
        case .previousSessionClosing: "The console is still closing the previous stream. Wait a moment and try again."
        case .duplicateSession: "A session is already starting. Wait for it to finish before trying again."
        case .hostRejected: "The host rejected stream setup. Check console availability and account access."
        case .timedOut: "Stream signaling timed out. Check your connection and try again."
        }
    }

    static func classify(_ code: String) -> Self {
        switch code {
        case "WaitingForServerToRegister": .consoleOffline
        case "StreamingDisabled", "RemotePlayDisabled": .remotePlayDisabled
        case "ServerStartStreamingNotFound": .previousSessionClosing
        case "DuplicateSessionRequest": .duplicateSession
        default: .hostRejected
        }
    }
}

enum SignalingPolling {
    static func delay(after elapsed: Duration) -> Duration {
        if elapsed < .seconds(2) { return .milliseconds(100) }
        if elapsed < .seconds(10) { return .milliseconds(250) }
        if elapsed < .seconds(30) { return .milliseconds(500) }
        return .seconds(1)
    }
}

enum SignalingResponse {
    static func decode<T: Decodable>(_ data: Data) throws -> T? {
        guard !data.isEmpty else { return nil }
        guard data.count <= 1_048_576,
              let outer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw CloudError.response
        }
        if let error = outer["errorDetails"] as? [String: Any] {
            throw SignalingFailure.classify(error["code"] as? String ?? "")
        }
        guard let response = outer["exchangeResponse"], !(response is NSNull) else { return nil }
        let payload: Data
        if let text = response as? String {
            guard !text.isEmpty else { return nil }
            payload = Data(text.utf8)
        } else {
            guard JSONSerialization.isValidJSONObject(response) else { throw CloudError.response }
            payload = try JSONSerialization.data(withJSONObject: response)
        }
        do {
            if let answer = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
               let status = answer["status"] as? String, status != "success" {
                throw SignalingFailure.classify(status)
            }
            return try JSONDecoder().decode(T.self, from: payload)
        } catch let failure as SignalingFailure { throw failure }
        catch { throw CloudError.response }
    }
}

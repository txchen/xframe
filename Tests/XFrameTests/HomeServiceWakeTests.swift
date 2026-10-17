import Foundation
import Testing
@testable import XFrame

private final class WakeProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        #expect(request.url?.path == "/commands")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 20)
        #expect(request.value(forHTTPHeaderField: "x-xbl-contract-version") == "4")
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(payload?["type"] as? String == "Power")
        #expect(payload?["command"] as? String == "WakeUp")
        let parameters = payload?["parameters"] as? [[String: String]]
        #expect(parameters == [[:]])
        let mode = payload?["linkedXboxId"] as? String ?? ""
        if mode == "timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        // OpenXbox smartglass/models.py CommandResponse makes result optional.
        let response: String
        switch mode {
        case "accepted": response = #"{"destination":{"id":"accepted"},"opId":"operation","status":{"errorCode":"OK"}}"#
        case "rejected": response = #"{"result":"","destination":{},"opId":"operation","status":{"errorCode":"RemoteManagementDisabled"}}"#
        default: response = #"{"result":""}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func wakeUsesDocumentedPayloadAndAcceptsResponseWithoutResult() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [WakeProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let service = try HomeService(credential: nil, expires: .distantFuture,
        webToken: "test", userHash: "test", session: session)
    try await service.wake("accepted")
    for id in ["rejected", "malformed"] {
        await #expect { try await service.wake(id) } throws: { error in
            if case CloudError.response = error { return true }
            return false
        }
    }
    await #expect { try await service.wake("timeout") } throws: { error in
        if case CloudError.network = error { return true }
        return false
    }
}

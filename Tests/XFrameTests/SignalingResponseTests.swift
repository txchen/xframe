import Foundation
import Testing
@testable import XFrame

private struct SDPAnswer: Decodable { let sdp: String }

@Test func signalingAcceptsStringAndObjectAnswers() throws {
    for body in [#"{"exchangeResponse":"{\"sdp\":\"answer\"}"}"#,
                 #"{"exchangeResponse":{"sdp":"answer","input":8}}"#] {
        let answer: SDPAnswer? = try SignalingResponse.decode(Data(body.utf8))
        #expect(answer?.sdp == "answer")
    }
    let candidates: [CloudICECandidate]? = try SignalingResponse.decode(Data(#"{"exchangeResponse":[{"candidate":"candidate","sdpMid":"0","sdpMLineIndex":"1"}]}"#.utf8))
    #expect(candidates?.first?.sdpMLineIndex == 1)
}

@Test func signalingPendingIsDifferentFromMalformed() throws {
    for body in ["", "{}", #"{"exchangeResponse":""}"#, #"{"exchangeResponse":null}"#] {
        let result: SDPAnswer? = try SignalingResponse.decode(Data(body.utf8))
        #expect(result == nil)
    }
    for body in [#"{"exchangeResponse":"broken"}"#, #"{"exchangeResponse":12}"#] {
        #expect(throws: (any Error).self) {
            let _: SDPAnswer? = try SignalingResponse.decode(Data(body.utf8))
        }
    }
}

@Test func signalingRejectsHostFailuresWithoutLeakingMessages() {
    for body in [#"{"errorDetails":{"code":"WaitingForServerToRegister","message":"secret"}}"#,
                 #"{"exchangeResponse":{"status":"DuplicateSessionRequest","errorDetails":"secret"}}"#] {
        do {
            let _: SDPAnswer? = try SignalingResponse.decode(Data(body.utf8))
            Issue.record("Host failure should terminate polling")
        } catch {
            #expect(error is SignalingFailure)
            #expect(!error.localizedDescription.contains("secret"))
        }
    }
}

@Test func signalingPollingSlowsDownAsSetupWaits() {
    #expect(SignalingPolling.delay(after: .zero) == .milliseconds(100))
    #expect(SignalingPolling.delay(after: .seconds(2)) == .milliseconds(250))
    #expect(SignalingPolling.delay(after: .seconds(10)) == .milliseconds(500))
    #expect(SignalingPolling.delay(after: .seconds(30)) == .seconds(1))
}

private final class SignalingProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body: String
        if request.httpMethod == "POST" { body = "{}" }
        else if request.url!.path.contains("failure") {
            body = #"{"errorDetails":{"code":"WaitingForServerToRegister"}}"#
        } else { body = #"{"exchangeResponse":{"sdp":"v=0"}}"# }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func signalingServiceUsesParserAndPropagatesHostFailure() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SignalingProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let token = CloudToken(gsToken: "test", durationInSeconds: 3600, market: "US",
        offeringSettings: .init(regions: [.init(name: "test", baseUri: URL(string: "https://test.xboxlive.com")!, isDefault: true)]))
    let service = try CloudService(credential: token, expires: .distantFuture, session: session)
    let answer = try await service.exchangeSDP(at: URL(string: "https://test.xboxlive.com/v5/sessions/cloud/good")!, offer: "v=0")
    #expect(answer == "v=0")
    await #expect(throws: SignalingFailure.self) {
        try await service.exchangeSDP(at: URL(string: "https://test.xboxlive.com/v5/sessions/cloud/failure")!, offer: "v=0")
    }
}

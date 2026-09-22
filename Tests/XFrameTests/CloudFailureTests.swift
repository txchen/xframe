import Foundation
import Testing
@testable import XFrame

@Test func cloudFailureCodeDoesNotExposeResponseMessages() {
    #expect(CloudService.failureCode(Data(#"{"code":"NoEntitlement"}"#.utf8)) == "NoEntitlement")
    #expect(CloudService.failureCode(Data(#"{"error":{"code":"NotEntitled","message":"secret"},"token":"secret"}"#.utf8)) == "NotEntitled")
    #expect(CloudService.failureCode(Data(#"{"code":"InvalidTitle","message":"secret"}"#.utf8)) == "InvalidTitle")
    for body in [#"{"message":"secret"}"#, #"{"code":"https://private.example"}"#, #"{"code":"token.with.signature"}"#, #"{"code":123}"#, "invalid"] {
        #expect(CloudService.failureCode(Data(body.utf8)) == nil)
    }
    #expect(CloudService.failureCode(Data(repeating: 65, count: 65_537)) == nil)
}

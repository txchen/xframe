import Testing
@testable import XFrame

@Test func presentationQueueAllowsTwoFramesUntilOneIsPresented() throws {
    let queue = PresentationQueue()
    let first = try #require(queue.reserve(enforcingLimit: true))
    let second = try #require(queue.reserve(enforcingLimit: true))
    #expect(queue.reserve(enforcingLimit: true) == nil)
    first.finish()
    let next = try #require(queue.reserve(enforcingLimit: true))
    withExtendedLifetime((second, next)) {
        #expect(queue.reserve(enforcingLimit: true) == nil)
    }
}

@Test func abandoningAnUnsubmittedFrameReturnsItsReservation() throws {
    let queue = PresentationQueue()
    let pending = try #require(queue.reserve(enforcingLimit: true))
    var abandoned = queue.reserve(enforcingLimit: true)
    withExtendedLifetime(abandoned) {
        #expect(queue.reserve(enforcingLimit: true) == nil)
    }
    abandoned = nil
    let replacement = try #require(queue.reserve(enforcingLimit: true))
    withExtendedLifetime((pending, replacement)) {
        #expect(queue.reserve(enforcingLimit: true) == nil)
    }
}

@Test func failureAndLatePresentationReturnTheSameReservationOnlyOnce() async throws {
    let queue = PresentationQueue()
    let failed = try #require(queue.reserve(enforcingLimit: true))
    let pending = try #require(queue.reserve(enforcingLimit: true))
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<20 { group.addTask { failed.finish() } }
    }
    let next = try #require(queue.reserve(enforcingLimit: true))
    withExtendedLifetime((pending, next)) {
        #expect(queue.reserve(enforcingLimit: true) == nil)
    }
}

@Test func switchingToTheBoundedPathWaitsForOlderModePresentations() throws {
    let queue = PresentationQueue()
    let older = try (0..<3).map { _ in try #require(queue.reserve(enforcingLimit: false)) }
    #expect(queue.reserve(enforcingLimit: true) == nil)
    older[0].finish()
    #expect(queue.reserve(enforcingLimit: true) == nil)
    older[1].finish()
    let next = try #require(queue.reserve(enforcingLimit: true))
    withExtendedLifetime((older, next)) {
        #expect(queue.reserve(enforcingLimit: true) == nil)
    }
}

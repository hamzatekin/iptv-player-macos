import Foundation
import Testing
@testable import IPTVCore

@Suite struct ReconnectPolicyTests {
    @Test func streamThatNeverStartedIsNotRetried() {
        var policy = ReconnectPolicy()
        #expect(policy.delayAfterStop(playedFor: nil) == nil)
    }

    @Test func dropIsRetriedWithLongerWaitsThenGivenUp() {
        var policy = ReconnectPolicy()
        #expect(policy.delayAfterStop(playedFor: 30) == .seconds(2))
        // Each reconnect that fails before showing video counts as the next attempt.
        #expect(policy.delayAfterStop(playedFor: nil) == .seconds(5))
        #expect(policy.delayAfterStop(playedFor: nil) == .seconds(10))
        #expect(policy.delayAfterStop(playedFor: nil) == nil)
        #expect(policy.attempts == 3)
    }

    @Test func briefRecoveriesDoNotResetTheCount() {
        var policy = ReconnectPolicy()
        #expect(policy.delayAfterStop(playedFor: 30) == .seconds(2))
        #expect(policy.delayAfterStop(playedFor: 5) == .seconds(5))
        #expect(policy.delayAfterStop(playedFor: 5) == .seconds(10))
        #expect(policy.delayAfterStop(playedFor: 5) == nil)
    }

    @Test func playingSteadilyStartsOver() {
        var policy = ReconnectPolicy()
        _ = policy.delayAfterStop(playedFor: 30)
        _ = policy.delayAfterStop(playedFor: nil)
        #expect(policy.delayAfterStop(playedFor: ReconnectPolicy.steadyAfter) == .seconds(2))
    }
}

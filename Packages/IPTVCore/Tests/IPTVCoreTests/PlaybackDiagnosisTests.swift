import Foundation
import Synchronization
import Testing
@testable import IPTVCore

private struct FakeAPI: XtreamAPI {
    var account: Result<AccountInfo, Error>
    var probe: StreamProbe
    let probeCalls = Counter()

    func accountInfo() async throws -> AccountInfo { try account.get() }
    func liveCategories() async throws -> [LiveCategory] { [] }
    func liveStreams() async throws -> [LiveStream] { [] }
    func shortEPG(streamID: Int, limit: Int) async throws -> [EPGEntry] { [] }
    func liveStreamURL(streamID: Int) -> URL { URL(string: "http://fake.invalid/")! }
    func probeStream(streamID: Int) async -> StreamProbe {
        probeCalls.increment()
        return probe
    }
}

private final class Counter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

@Suite struct PlaybackDiagnosisTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let server = StreamServer(host: "203.0.113.7", port: 80)

    private func account(
        status: String = "Active", expires: Date? = nil, max: Int = 1, active: Int = 0
    ) -> AccountInfo {
        AccountInfo(
            isAuthenticated: true, status: status, expiresAt: expires, maxConnections: max,
            activeConnections: active, allowedOutputFormats: ["ts"], serverTimezone: nil
        )
    }

    private func diagnose(
        _ api: FakeAPI, recentlyPlayed: Bool = false, reach: NetworkFailure? = nil, reachCalls: Counter = Counter()
    ) async -> ProviderProblem {
        await PlaybackDiagnosis.run(client: api, streamID: 7, recentlyPlayed: recentlyPlayed, now: now, reach: { _ in
            reachCalls.increment()
            return reach
        })
    }

    @Test func accountErrorsStopEarly() async {
        let errors: [(Error, ProviderProblem)] = [
            (XtreamError.notAuthenticated, .loginRejected),
            (XtreamError.emptyResponse, .userAgentRejected),
            (URLError(.timedOut), .providerUnreachable(.timedOut)),
            (XtreamError.badStatus(503), .serverError(status: 503)),
        ]
        for (error, expected) in errors {
            let api = FakeAPI(account: .failure(error), probe: .answered(status: 200, redirect: nil))
            #expect(await diagnose(api) == expected)
            #expect(api.probeCalls.value == 0)
        }
    }

    @Test func badAccountStatusStopsBeforeTheStreamRequest() async {
        let api = FakeAPI(account: .success(account(status: "Banned")), probe: .answered(status: 200, redirect: nil))
        #expect(await diagnose(api) == .accountStatus("Banned"))
        #expect(api.probeCalls.value == 0)
    }

    @Test func expiredAccountStopsBeforeTheStreamRequest() async {
        let past = now.addingTimeInterval(-3600)
        let api = FakeAPI(account: .success(account(expires: past)), probe: .answered(status: 200, redirect: nil))
        #expect(await diagnose(api) == .expired(past))
        #expect(api.probeCalls.value == 0)
    }

    @Test func probeFailureIsReturned() async {
        for problem in [ProviderProblem.userAgentRejected, .providerUnreachable(.timedOut)] {
            let api = FakeAPI(account: .success(account()), probe: .failed(problem))
            let reachCalls = Counter()
            #expect(await diagnose(api, reachCalls: reachCalls) == problem)
            #expect(reachCalls.value == 0)
        }
    }

    @Test func redirectToUnreachableServer() async {
        let api = FakeAPI(account: .success(account()), probe: .answered(status: 302, redirect: server))
        #expect(await diagnose(api, reach: .timedOut) == .streamServerUnreachable(host: "203.0.113.7", .timedOut))
        #expect(await diagnose(api, reach: .refused) == .streamServerUnreachable(host: "203.0.113.7", .refused))
    }

    @Test func redirectToReachableServerMeansChannelOffline() async {
        let api = FakeAPI(account: .success(account()), probe: .answered(status: 302, redirect: server))
        let reachCalls = Counter()
        #expect(await diagnose(api, reach: nil, reachCalls: reachCalls) == .channelOffline)
        #expect(reachCalls.value == 1)
    }

    @Test func reachIsGivenTheRedirectServer() async {
        let api = FakeAPI(account: .success(account()), probe: .answered(status: 302, redirect: server))
        let seen = Mutex<StreamServer?>(nil)
        _ = await PlaybackDiagnosis.run(client: api, streamID: 7, now: now, reach: { s in
            seen.withLock { $0 = s }
            return nil
        })
        #expect(seen.withLock { $0 } == server)
    }

    @Test func redirectWithoutLocationIsUnexpected() async {
        let api = FakeAPI(account: .success(account()), probe: .answered(status: 302, redirect: nil))
        let reachCalls = Counter()
        #expect(await diagnose(api, reachCalls: reachCalls) == .unexpectedStatus(302))
        #expect(reachCalls.value == 0)
    }

    @Test func successStatusMeansChannelOffline() async {
        let api = FakeAPI(account: .success(account()), probe: .answered(status: 200, redirect: nil))
        let reachCalls = Counter()
        #expect(await diagnose(api, reachCalls: reachCalls) == .channelOffline)
        #expect(reachCalls.value == 0)
    }

    @Test func forbiddenWithFullConnectionsIsTheLimit() async {
        let api = FakeAPI(account: .success(account(max: 1, active: 1)), probe: .answered(status: 403, redirect: nil))
        #expect(await diagnose(api) == .connectionLimitReached(max: 1))
    }

    @Test func forbiddenWithFreeConnectionsIsForbidden() async {
        let api = FakeAPI(account: .success(account(max: 2, active: 1)), probe: .answered(status: 403, redirect: nil))
        #expect(await diagnose(api) == .forbidden)
    }

    @Test func goneOrMissingChannel() async {
        for status in [404, 410] {
            let api = FakeAPI(account: .success(account()), probe: .answered(status: status, redirect: nil))
            #expect(await diagnose(api) == .channelNotFound)
        }
    }

    @Test func otherStatusesUseTheHTTPMapping() async {
        let cases: [(Int, ProviderProblem)] = [
            (401, .loginRejected), (429, .throttled(status: 429)), (509, .throttled(status: 509)),
            (500, .serverError(status: 500)), (418, .unexpectedStatus(418)),
        ]
        for (status, expected) in cases {
            let api = FakeAPI(account: .success(account()), probe: .answered(status: status, redirect: nil))
            #expect(await diagnose(api) == expected)
        }
    }

    /// The API still redirects and the stream server is reachable, but the account shows the line is
    /// full: either the stream server enforced the limit, or the count includes the failed attempt.
    @Test func fullConnectionsAddConnectionInUseToChannelOffline() async {
        let full = account(max: 1, active: 1)
        let redirected = FakeAPI(account: .success(full), probe: .answered(status: 302, redirect: server))
        #expect(await diagnose(redirected) == .channelOfflineOrConnectionInUse(max: 1))
        let direct = FakeAPI(account: .success(full), probe: .answered(status: 200, redirect: nil))
        #expect(await diagnose(direct) == .channelOfflineOrConnectionInUse(max: 1))
    }

    /// Seen live: DMAX got 403 right after other channels played, while the account showed 0 of 1 in use.
    /// The IP and account work, so the refusal is about this channel (or the one just left).
    @Test func forbiddenAfterOtherChannelsPlayedIsThisChannel() async {
        for active in [0, 1] {
            let api = FakeAPI(account: .success(account(max: 1, active: active)), probe: .answered(status: 403, redirect: nil))
            #expect(await diagnose(api, recentlyPlayed: true) == .channelRefused)
        }
    }
}

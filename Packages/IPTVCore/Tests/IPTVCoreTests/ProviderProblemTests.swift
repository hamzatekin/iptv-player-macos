import Foundation
import Testing
@testable import IPTVCore

@Suite struct ProviderProblemTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func account(status: String = "Active", expires: Date? = nil) -> AccountInfo {
        AccountInfo(
            isAuthenticated: true, status: status, expiresAt: expires, maxConnections: 1,
            activeConnections: 0, allowedOutputFormats: ["ts"], serverTimezone: nil
        )
    }

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, NetworkFailure.offline),
        (.dataNotAllowed, .offline),
        (.internationalRoamingOff, .offline),
        (.cannotFindHost, .notFound),
        (.dnsLookupFailed, .notFound),
        (.cannotConnectToHost, .refused),
        (.timedOut, .timedOut),
        (.secureConnectionFailed, .other),
        (.badURL, .other),
    ])
    func networkFailureFromURLErrorCode(code: URLError.Code, expected: NetworkFailure) {
        #expect(NetworkFailure(code) == expected)
    }

    @Test func errorMapping() {
        #expect(ProviderProblem(error: XtreamError.notAuthenticated) == .loginRejected)
        #expect(ProviderProblem(error: XtreamError.emptyResponse) == .userAgentRejected)
        #expect(ProviderProblem(error: XtreamError.badStatus(429)) == .throttled(status: 429))
        #expect(ProviderProblem(error: XtreamError.badStatus(503)) == .serverError(status: 503))
        #expect(ProviderProblem(error: XtreamError.decoding("x")) == .badResponse)
        #expect(ProviderProblem(error: URLError(.timedOut)) == .providerUnreachable(.timedOut))
        #expect(ProviderProblem(error: URLError(.cannotFindHost)) == .providerUnreachable(.notFound))
        #expect(ProviderProblem(error: URLError(.notConnectedToInternet)) == .providerUnreachable(.offline))
        #expect(ProviderProblem(error: CocoaError(.fileNoSuchFile)) == .badResponse)
    }

    @Test func httpStatusMapping() {
        #expect(ProviderProblem(httpStatus: 401) == .loginRejected)
        #expect(ProviderProblem(httpStatus: 403) == .forbidden)
        #expect(ProviderProblem(httpStatus: 429) == .throttled(status: 429))
        #expect(ProviderProblem(httpStatus: 509) == .throttled(status: 509))
        #expect(ProviderProblem(httpStatus: 500) == .serverError(status: 500))
        #expect(ProviderProblem(httpStatus: 599) == .serverError(status: 599))
        #expect(ProviderProblem(httpStatus: 418) == .unexpectedStatus(418))
        #expect(ProviderProblem(httpStatus: 404) == .unexpectedStatus(404))
    }

    @Test func activeAccountIsFine() {
        #expect(ProviderProblem(account: account(), now: now) == nil)
        #expect(ProviderProblem(account: account(status: "active"), now: now) == nil)
        #expect(ProviderProblem(account: account(status: "ACTIVE", expires: now.addingTimeInterval(60)), now: now) == nil)
        #expect(ProviderProblem(account: account(status: ""), now: now) == nil)
    }

    @Test func inactiveStatusIsReported() {
        #expect(ProviderProblem(account: account(status: "Banned"), now: now) == .accountStatus("Banned"))
        #expect(ProviderProblem(account: account(status: "Disabled"), now: now) == .accountStatus("Disabled"))
    }

    @Test func pastExpiryIsReported() {
        let past = now.addingTimeInterval(-60)
        #expect(ProviderProblem(account: account(expires: past), now: now) == .expired(past))
    }

    @Test func statusIsCheckedBeforeExpiry() {
        let past = now.addingTimeInterval(-60)
        #expect(ProviderProblem(account: account(status: "Expired", expires: past), now: now) == .accountStatus("Expired"))
    }

    @Test func connectionLimitIsNotPartOfTheAccountCheck() {
        var full = account()
        full.activeConnections = 1
        #expect(ProviderProblem(account: full, now: now) == nil)
    }
}

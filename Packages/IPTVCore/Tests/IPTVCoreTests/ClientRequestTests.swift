import Foundation
import Testing
@testable import IPTVCore

@Suite struct ClientRequestTests {
    private func client(host: String, password: String = "pw", session: URLSession = StubURLProtocol.session()) -> XtreamClient {
        XtreamClient(
            credentials: XtreamCredentials(server: URL(string: "http://\(host):8080")!, username: "demo", password: password),
            userAgent: "TestAgent/1.0",
            session: session
        )
    }

    private func ok(_ request: URLRequest, _ body: String, status: Int = 200) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    /// Request URLs hold the password, and URLCache stores rows keyed by URL on disk.
    @Test func defaultSessionCachesNothing() {
        let config = XtreamClient.defaultSession.configuration
        #expect(config.urlCache == nil)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func requestCarriesUserAgentAndQueryItems() async throws {
        let host = "ua.test"
        let seen = Seen()
        StubURLProtocol.register(host: host) { request in
            seen.set(request)
            return self.ok(request, #"{"epg_listings":[]}"#)
        }
        _ = try await client(host: host, password: "p&w+x y").shortEPG(streamID: 42, limit: 3)

        let request = try #require(seen.value)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "TestAgent/1.0")
        #expect(request.timeoutInterval == 20)
        let url = try #require(request.url)
        #expect(url.path() == "/player_api.php")
        let items = Dictionary(
            uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) }
        )
        #expect(items["username"] == "demo")
        #expect(items["password"] == "p&w+x y")
        #expect(items["action"] == "get_short_epg")
        #expect(items["stream_id"] == "42")
        #expect(items["limit"] == "3")
        #expect(url.absoluteString.contains("password=p%26w%2Bx%20y"))
    }

    @Test func accountInfoSendsNoAction() async throws {
        let host = "noaction.test"
        let seen = Seen()
        StubURLProtocol.register(host: host) { request in
            seen.set(request)
            return self.ok(request, try String(decoding: fixture("account_info"), as: UTF8.self))
        }
        let info = try await client(host: host).accountInfo()
        #expect(info.isAuthenticated)
        let query = try #require(seen.value?.url?.query())
        #expect(!query.contains("action"))
    }

    @Test func emptyBodyIsEmptyResponse() async {
        let host = "empty.test"
        StubURLProtocol.register(host: host) { self.ok($0, "") }
        await #expect(throws: XtreamError.emptyResponse) { try await client(host: host).liveStreams() }
    }

    @Test func badStatus() async {
        let host = "status.test"
        StubURLProtocol.register(host: host) { self.ok($0, "nope", status: 403) }
        await #expect(throws: XtreamError.badStatus(403)) { try await client(host: host).liveCategories() }
    }

    @Test func hangUpIsEmptyResponse() async {
        let host = "hangup.test"
        StubURLProtocol.register(host: host) { _ in throw URLError(.networkConnectionLost) }
        await #expect(throws: XtreamError.emptyResponse) { try await client(host: host).liveStreams() }
    }

    @Test func otherURLErrorsPropagate() async {
        let host = "timeout.test"
        StubURLProtocol.register(host: host) { _ in throw URLError(.timedOut) }
        do {
            _ = try await client(host: host).liveStreams()
            Issue.record("expected a URLError")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record("expected a URLError, got \(error)")
        }
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?
    func set(_ r: URLRequest) { lock.withLock { request = r } }
    var value: URLRequest? { lock.withLock { request } }
}

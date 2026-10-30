import Foundation
import Synchronization
import Testing
@testable import IPTVCore

@Suite struct ProbeStreamTests {
    private func client(host: String, port: Int = 8080) -> XtreamClient {
        XtreamClient(
            credentials: XtreamCredentials(server: URL(string: "http://\(host):\(port)")!, username: "demo", password: "secret"),
            userAgent: "TestAgent/1.0",
            session: StubURLProtocol.session()
        )
    }

    private func respond(_ request: URLRequest, status: Int, headers: [String: String] = [:]) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, Data())
    }

    @Test func absoluteLocationKeepsOnlyHostAndPort() async {
        let host = "probe-abs.test"
        StubURLProtocol.register(host: host) { request in
            self.respond(request, status: 302, headers: ["Location": "http://203.0.113.7:8000/live/demo/secret/7.ts?token=abc"])
        }
        let result = await client(host: host).probeStream(streamID: 7)
        #expect(result == .answered(status: 302, redirect: StreamServer(host: "203.0.113.7", port: 8000)))
    }

    /// Following the redirect would open the real stream on the stream server, using the one connection.
    @Test func neverFollowsTheRedirect() async {
        let host = "probe-follow.test", target = "probe-target.test"
        let targetHits = Mutex(0)
        StubURLProtocol.register(host: target) { request in
            targetHits.withLock { $0 += 1 }
            return self.respond(request, status: 200)
        }
        StubURLProtocol.register(host: host) { request in
            self.respond(request, status: 302, headers: ["Location": "http://\(target)/live/demo/secret/7.ts"])
        }
        let result = await client(host: host).probeStream(streamID: 7)
        #expect(result == .answered(status: 302, redirect: StreamServer(host: target, port: 80)))
        #expect(targetHits.withLock { $0 } == 0)
    }

    @Test func locationWithoutPortDefaultsByScheme() async {
        let http = "probe-http.test"
        StubURLProtocol.register(host: http) { request in
            self.respond(request, status: 302, headers: ["Location": "http://stream.example/live/x.ts"])
        }
        let https = "probe-https.test"
        StubURLProtocol.register(host: https) { request in
            self.respond(request, status: 301, headers: ["Location": "https://stream.example/live/x.ts"])
        }
        #expect(await client(host: http).probeStream(streamID: 1)
            == .answered(status: 302, redirect: StreamServer(host: "stream.example", port: 80)))
        #expect(await client(host: https).probeStream(streamID: 1)
            == .answered(status: 301, redirect: StreamServer(host: "stream.example", port: 443)))
    }

    @Test func relativeLocationResolvesAgainstTheRequestServer() async {
        let host = "probe-rel.test"
        StubURLProtocol.register(host: host) { request in
            self.respond(request, status: 302, headers: ["Location": "/other/7.ts?token=abc"])
        }
        let result = await client(host: host, port: 8080).probeStream(streamID: 7)
        #expect(result == .answered(status: 302, redirect: StreamServer(host: host, port: 8080)))
    }

    @Test func redirectWithoutLocationHasNoServer() async {
        let host = "probe-noloc.test"
        StubURLProtocol.register(host: host) { request in self.respond(request, status: 302) }
        #expect(await client(host: host).probeStream(streamID: 7) == .answered(status: 302, redirect: nil))
    }

    @Test func nonRedirectStatusIgnoresLocation() async {
        let host = "probe-403.test"
        StubURLProtocol.register(host: host) { request in
            self.respond(request, status: 403, headers: ["Location": "http://elsewhere.test/"])
        }
        #expect(await client(host: host).probeStream(streamID: 7) == .answered(status: 403, redirect: nil))
    }

    @Test func sendsUserAgentAndShortTimeoutToTheLiveURL() async throws {
        let host = "probe-ua.test"
        let seen = Mutex<URLRequest?>(nil)
        StubURLProtocol.register(host: host) { request in
            seen.withLock { $0 = request }
            return self.respond(request, status: 200)
        }
        let c = client(host: host)
        _ = await c.probeStream(streamID: 42)
        let request = try #require(seen.withLock { $0 })
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "TestAgent/1.0")
        #expect(request.timeoutInterval == 10)
        #expect(request.url == c.liveStreamURL(streamID: 42))
    }

    @Test(arguments: [URLError.Code.networkConnectionLost, .badServerResponse, .cannotParseResponse, .zeroByteResource])
    func hangUpMeansUserAgentRejected(code: URLError.Code) async {
        let host = "probe-hangup-\(code.rawValue).test"
        StubURLProtocol.register(host: host) { _ in throw URLError(code) }
        #expect(await client(host: host).probeStream(streamID: 7) == .failed(.userAgentRejected))
    }

    @Test func otherURLErrorsMeanProviderUnreachable() async {
        let host = "probe-timeout.test"
        StubURLProtocol.register(host: host) { _ in throw URLError(.timedOut) }
        #expect(await client(host: host).probeStream(streamID: 7) == .failed(.providerUnreachable(.timedOut)))
    }

    @Test func resultNeverContainsTheLogin() async {
        let host = "probe-secret.test"
        StubURLProtocol.register(host: host) { request in
            self.respond(request, status: 302, headers: ["Location": "http://1.2.3.4:80/live/demo/secret/7.ts"])
        }
        let result = await client(host: host).probeStream(streamID: 7)
        #expect(!String(describing: result).contains("secret"))
    }
}

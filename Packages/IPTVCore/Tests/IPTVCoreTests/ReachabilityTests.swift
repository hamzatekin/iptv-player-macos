import Foundation
import Network
import Synchronization
import Testing
@testable import IPTVCore

@Suite struct ReachabilityTests {
    /// Starts a listener on a free local port and returns it with the port once ready.
    private func listen() async throws -> (NWListener, Int) {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { $0.cancel() }
        let port: Int = await withCheckedContinuation { continuation in
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                let first = resumed.withLock { done -> Bool in defer { done = true }; return !done }
                if first { continuation.resume(returning: Int(listener.port?.rawValue ?? 0)) }
            }
            listener.start(queue: .global())
        }
        return (listener, port)
    }

    @Test func openLocalPortIsReachable() async throws {
        let (listener, port) = try await listen()
        defer { listener.cancel() }
        try #require(port > 0)
        #expect(await Reachability.check(StreamServer(host: "127.0.0.1", port: port)) == nil)
    }

    @Test func closedLocalPortIsRefused() async throws {
        let (listener, port) = try await listen()
        listener.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await Reachability.check(StreamServer(host: "127.0.0.1", port: port)) == .refused)
    }

    @Test func invalidPortIsOther() async {
        #expect(await Reachability.check(StreamServer(host: "127.0.0.1", port: 70000)) == .other)
        #expect(await Reachability.check(StreamServer(host: "127.0.0.1", port: 0)) == .other)
    }

    @Test func posixErrorsMapToFailures() {
        #expect(Reachability.failure(for: .posix(.ETIMEDOUT)) == .timedOut)
        #expect(Reachability.failure(for: .posix(.EHOSTUNREACH)) == .timedOut)
        #expect(Reachability.failure(for: .posix(.ENETUNREACH)) == .timedOut)
        #expect(Reachability.failure(for: .posix(.ECONNREFUSED)) == .refused)
        #expect(Reachability.failure(for: .posix(.EACCES)) == .other)
        #expect(Reachability.failure(for: .dns(DNSServiceErrorType(-65537))) == .notFound)
    }
}

import Foundation
import Network
import Synchronization

public enum Reachability {
    /// Opens and closes a bare TCP connection. No HTTP is sent, so the provider sees no stream
    /// request. Nil means reachable.
    public static func check(_ server: StreamServer, timeout: Duration = .seconds(6)) async -> NetworkFailure? {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: server.port)), server.port > 0, server.port <= 65535 else {
            return .other
        }
        let connection = NWConnection(host: NWEndpoint.Host(server.host), port: port, using: .tcp)
        let queue = DispatchQueue(label: "IPTVCore.Reachability")
        let gate = Gate()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<NetworkFailure?, Never>) in
                gate.install(continuation) { connection.cancel() }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        gate.finish(nil)
                    case .failed(let error), .waiting(let error):
                        // `waiting` is where a refused or unreachable connect lands; it would retry forever.
                        gate.finish(failure(for: error))
                    case .cancelled:
                        gate.finish(.other)
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
                queue.asyncAfter(deadline: .now() + max(seconds, 0)) { gate.finish(.timedOut) }
            }
        } onCancel: {
            gate.finish(.other)
        }
    }

    static func failure(for error: NWError) -> NetworkFailure {
        switch error {
        case .posix(let code):
            switch code {
            case .ETIMEDOUT, .EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN, .ENETDOWN: return .timedOut
            case .ECONNREFUSED: return .refused
            default: return .other
            }
        case .dns: return .notFound
        default: return .other
        }
    }

    /// Resumes the continuation exactly once and closes the connection.
    private final class Gate: Sendable {
        private struct State {
            var continuation: CheckedContinuation<NetworkFailure?, Never>?
            var cleanup: (@Sendable () -> Void)?
            var result: NetworkFailure??
        }
        private let state = Mutex(State())

        func install(_ continuation: CheckedContinuation<NetworkFailure?, Never>, cleanup: @escaping @Sendable () -> Void) {
            let early = state.withLock { state -> NetworkFailure?? in
                if let result = state.result { return result }
                state.continuation = continuation
                state.cleanup = cleanup
                return nil
            }
            if let early {
                continuation.resume(returning: early)
                cleanup()
            }
        }

        func finish(_ result: NetworkFailure?) {
            let (continuation, cleanup) = state.withLock { state -> (CheckedContinuation<NetworkFailure?, Never>?, (@Sendable () -> Void)?) in
                guard state.result == nil else { return (nil, nil) }
                state.result = .some(result)
                defer { state.continuation = nil; state.cleanup = nil }
                return (state.continuation, state.cleanup)
            }
            continuation?.resume(returning: result)
            cleanup?()
        }
    }
}

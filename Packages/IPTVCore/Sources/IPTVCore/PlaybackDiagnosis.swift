import Foundation

public enum PlaybackDiagnosis {
    /// Why a stream that mpv failed to open didn't play. At most three requests: account info,
    /// one stream URL request that stops at the redirect, one bare TCP connect. `recentlyPlayed`:
    /// another stream played a few minutes ago, so this IP and account do get streams.
    public static func run(
        client: any XtreamAPI, streamID: Int, recentlyPlayed: Bool = false, now: Date = .now,
        reach: @Sendable (StreamServer) async -> NetworkFailure? = { await Reachability.check($0) }
    ) async -> ProviderProblem {
        let account: AccountInfo
        do {
            account = try await client.accountInfo()
        } catch {
            return ProviderProblem(error: error)
        }
        if let problem = ProviderProblem(account: account, now: now) { return problem }
        // Everything answered but the stream still failed. A full line may be the cause (the stream
        // server, not the API server, may enforce the limit), or only count the failed attempt itself.
        let streamFailedAnyway: ProviderProblem = account.activeConnections >= account.maxConnections
            ? .channelOfflineOrConnectionInUse(max: account.maxConnections)
            : .channelOffline

        switch await client.probeStream(streamID: streamID) {
        case .failed(let problem):
            return problem
        case .answered(let status, let redirect):
            switch status {
            case 300...399:
                guard let server = redirect else { return .unexpectedStatus(status) }
                if let failure = await reach(server) {
                    return .streamServerUnreachable(host: server.host, failure)
                }
                return streamFailedAnyway
            case 200...299:
                return streamFailedAnyway
            case 403 where recentlyPlayed:
                return .channelRefused
            case 403:
                return account.activeConnections >= account.maxConnections
                    ? .connectionLimitReached(max: account.maxConnections)
                    : .forbidden
            case 404, 410:
                return .channelNotFound
            default:
                return ProviderProblem(httpStatus: status)
            }
        }
    }
}

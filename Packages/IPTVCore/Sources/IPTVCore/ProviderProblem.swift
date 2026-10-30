import Foundation

/// How a network request failed before any HTTP answer arrived.
public enum NetworkFailure: Equatable, Sendable {
    /// This Mac has no internet.
    case offline
    /// The host name doesn't resolve.
    case notFound
    /// Something answered and refused the connection.
    case refused
    /// Nothing answered in time, or the host or network is unreachable.
    case timedOut
    case other

    public init(_ code: URLError.Code) {
        switch code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            self = .offline
        case .cannotFindHost, .dnsLookupFailed:
            self = .notFound
        case .cannotConnectToHost:
            self = .refused
        case .timedOut:
            self = .timedOut
        default:
            self = .other
        }
    }
}

/// Why a request to the provider, or a live stream, failed. Holds no URLs: stream and API URLs
/// contain the username and password.
public enum ProviderProblem: Equatable, Sendable {
    /// The API server didn't answer.
    case providerUnreachable(NetworkFailure)
    /// The API works, but the stream server it redirects to doesn't.
    case streamServerUnreachable(host: String, NetworkFailure)
    /// The server hung up without answering.
    case userAgentRejected
    /// `auth` was 0 or HTTP 401.
    case loginRejected
    /// `status` isn't "Active", for example "Banned".
    case accountStatus(String)
    case expired(Date)
    case connectionLimitReached(max: Int)
    /// HTTP 403: IP blocked or account restricted.
    case forbidden
    /// HTTP 429 or 509.
    case throttled(status: Int)
    /// HTTP 5xx.
    case serverError(status: Int)
    /// HTTP 404 or 410 on the stream URL.
    case channelNotFound
    /// Everything answered, but the stream itself didn't play.
    case channelOffline
    /// As `channelOffline`, but the account showed every connection in use. The count may still
    /// include the failed attempt itself, so either cause is possible.
    case channelOfflineOrConnectionInUse(max: Int)
    /// HTTP 403 for this stream although another stream played recently: the IP and account work,
    /// so the provider refuses this channel, or still counts the channel just left.
    case channelRefused
    /// The server sent something unreadable.
    case badResponse
    case unexpectedStatus(Int)

    /// From any error `XtreamClient` throws.
    public init(error: Error) {
        if let error = error as? XtreamError {
            switch error {
            case .notAuthenticated: self = .loginRejected
            case .emptyResponse: self = .userAgentRejected
            case .badStatus(let status): self = ProviderProblem(httpStatus: status)
            case .decoding: self = .badResponse
            }
        } else if let error = error as? URLError {
            self = .providerUnreachable(NetworkFailure(error.code))
        } else {
            self = .badResponse
        }
    }

    public init(httpStatus: Int) {
        switch httpStatus {
        case 401: self = .loginRejected
        case 403: self = .forbidden
        case 429, 509: self = .throttled(status: httpStatus)
        case 500...599: self = .serverError(status: httpStatus)
        default: self = .unexpectedStatus(httpStatus)
        }
    }

    /// Nil when the account is fine. Checks the status (empty counts as fine), then the expiry
    /// against `now`. Doesn't look at connections.
    public init?(account: AccountInfo, now: Date) {
        let status = account.status.trimmingCharacters(in: .whitespacesAndNewlines)
        if !status.isEmpty, status.caseInsensitiveCompare("Active") != .orderedSame {
            self = .accountStatus(status)
        } else if let expiresAt = account.expiresAt, expiresAt < now {
            self = .expired(expiresAt)
        } else {
            return nil
        }
    }
}

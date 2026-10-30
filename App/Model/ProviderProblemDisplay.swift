import Foundation
import IPTVCore

extension ProviderProblem {
    var title: String {
        switch self {
        case .providerUnreachable(.offline): "You're offline"
        case .providerUnreachable(.notFound): "Server not found"
        case .providerUnreachable: "Can't reach the provider"
        // Only a silent timeout looks like an ISP block; a refusal means the server is there but not serving.
        case .streamServerUnreachable(_, .timedOut): "Stream server blocked on this network"
        case .streamServerUnreachable(_, .refused): "Stream server isn't accepting connections"
        case .streamServerUnreachable: "Can't reach the stream server"
        case .userAgentRejected: "The server hung up"
        case .loginRejected: "Login rejected"
        case .accountStatus(let status): "Account \(status.lowercased())"
        case .expired: "Subscription expired"
        case .connectionLimitReached: "Connection already in use"
        case .forbidden: "Access refused"
        case .throttled: "Too many requests"
        case .serverError: "Provider's server error"
        case .channelNotFound: "Channel not found"
        case .channelOffline: "This channel isn't sending video"
        case .channelOfflineOrConnectionInUse: "This channel didn't play"
        case .channelRefused: "The provider refused this channel"
        case .badResponse: "Unexpected answer from the server"
        case .unexpectedStatus(let status): "Unexpected answer (HTTP \(status))"
        }
    }

    var detail: String {
        switch self {
        case .providerUnreachable(.offline):
            "This Mac isn't connected to the internet."
        case .providerUnreachable(.notFound):
            "The server address doesn't exist. Check it, or ask the provider whether it changed."
        case .providerUnreachable(let failure):
            "The provider's server \(failure.phrase). It may be down, or your network may be blocking it."
        case .streamServerUnreachable(let host, .timedOut):
            "The provider's server works, but its stream server (\(host)) didn't answer. "
                + "That usually means your internet provider blocks it. Other networks may work."
        case .streamServerUnreachable(let host, .refused):
            "The provider's server works, but its stream server (\(host)) refused the connection. "
                + "It is probably down: try again later."
        case .streamServerUnreachable(let host, let failure):
            "The provider's server works, but its stream server (\(host)) \(failure.phrase)."
        case .userAgentRejected:
            "The provider drops apps it doesn't recognise. Try another user agent in Settings."
        case .loginRejected:
            "The username or password is wrong, or the provider has turned the account off."
        case .accountStatus(let status):
            "The provider reports this account as \"\(status)\"."
        case .expired(let date):
            "It ended on \(date.formatted(date: .long, time: .omitted))."
        case .connectionLimitReached(let max):
            "Your plan allows \(max) connection\(max == 1 ? "" : "s") and \(max == 1 ? "it is" : "they are") in use. "
                + "Stop watching on the other device, then retry."
        case .forbidden:
            "The provider refused the request (HTTP 403). Your IP may be blocked, or the account restricted."
        case .throttled(let status):
            "The provider is limiting requests (HTTP \(status)). Wait a few minutes, then retry."
        case .serverError(let status):
            "The server failed with HTTP \(status). This is usually temporary."
        case .channelNotFound:
            "The provider no longer has this stream. Refresh the channel list."
        case .channelOffline:
            "The provider's servers answered, but this channel didn't play. It may be off air: try another channel."
        case .channelOfflineOrConnectionInUse(let max):
            "It may be off air, or your connection\(max == 1 ? "" : "s") may be in use on another device. "
                + "Try another channel, or stop watching elsewhere and retry."
        case .channelRefused:
            "Other channels play, so your IP and account are fine. The provider is refusing this channel "
                + "(HTTP 403), or still counts the one you just left: retry in a few seconds."
        case .badResponse:
            "The server sent something the app couldn't read."
        case .unexpectedStatus(let status):
            "The server answered with HTTP \(status), which the app doesn't expect. Check the server address."
        }
    }

    var systemImage: String {
        switch self {
        case .providerUnreachable(.offline): "wifi.slash"
        case .providerUnreachable, .streamServerUnreachable: "network.slash"
        case .loginRejected, .accountStatus, .expired, .forbidden: "person.crop.circle.badge.xmark"
        case .connectionLimitReached: "person.2.fill"
        case .throttled: "hourglass"
        case .channelNotFound, .channelOffline, .channelOfflineOrConnectionInUse, .channelRefused: "tv.slash"
        default: "exclamationmark.triangle"
        }
    }
}

private extension NetworkFailure {
    var phrase: String {
        switch self {
        case .offline: "can't be reached while offline"
        case .notFound: "has an address that doesn't exist"
        case .refused: "refused the connection"
        case .timedOut: "didn't answer"
        case .other: "couldn't be reached"
        }
    }
}

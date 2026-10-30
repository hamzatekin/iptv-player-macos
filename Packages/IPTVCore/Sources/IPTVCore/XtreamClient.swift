import Foundation

public protocol XtreamAPI: Sendable {
    func accountInfo() async throws -> AccountInfo
    func liveCategories() async throws -> [LiveCategory]
    func liveStreams() async throws -> [LiveStream]
    /// Now/next and a few more programmes for one stream.
    func shortEPG(streamID: Int, limit: Int) async throws -> [EPGEntry]
    func liveStreamURL(streamID: Int) -> URL
    /// Asks for the live URL and stops at the headers (never reads the stream), without following
    /// the redirect. For diagnosing a stream that failed to play.
    func probeStream(streamID: Int) async -> StreamProbe
}

/// Host and port of a stream server. Holds no path or query: those contain the login.
public struct StreamServer: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

public enum StreamProbe: Equatable, Sendable {
    /// `redirect` is the host and port of `Location` on a 3xx; the port defaults to 80 or 443 by scheme.
    case answered(status: Int, redirect: StreamServer?)
    /// `providerUnreachable(...)` or `userAgentRejected`.
    case failed(ProviderProblem)
}

public enum XtreamError: Error, Equatable {
    /// `auth` was 0: wrong username or password, or the account is disabled.
    case notAuthenticated
    case badStatus(Int)
    /// The server closed the connection or sent an empty body. This server does that when it
    /// rejects the user agent.
    case emptyResponse
    case decoding(String)
}

/// Talks to `player_api.php`. Every request sends `userAgent`, because the provider drops
/// requests from user agents it doesn't recognise.
public struct XtreamClient: XtreamAPI {
    public let credentials: XtreamCredentials
    public let userAgent: String
    private let session: URLSession

    public init(credentials: XtreamCredentials, userAgent: String, session: URLSession = Self.defaultSession) {
        self.credentials = credentials
        self.userAgent = userAgent
        self.session = session
    }

    /// Caches nothing: URLSession.shared stores responses on disk keyed by URL, and every request
    /// URL here contains the password.
    public static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    public func accountInfo() async throws -> AccountInfo {
        try Self.decodeAccountInfo(await fetch(action: nil))
    }

    public func liveCategories() async throws -> [LiveCategory] {
        try Self.decodeLiveCategories(await fetch(action: "get_live_categories"))
    }

    public func liveStreams() async throws -> [LiveStream] {
        try Self.decodeLiveStreams(await fetch(action: "get_live_streams"))
    }

    public func shortEPG(streamID: Int, limit: Int) async throws -> [EPGEntry] {
        let extra = [("stream_id", String(streamID)), ("limit", String(limit))]
        return try Self.decodeShortEPG(await fetch(action: "get_short_epg", extra: extra))
    }

    /// `/live/<user>/<pass>/<id>.ts`. The account only allows the `ts` output format.
    public func liveStreamURL(streamID: Int) -> URL {
        credentials.server
            .appending(path: "live")
            .appending(path: credentials.username)
            .appending(path: credentials.password)
            .appending(path: "\(streamID).ts")
    }

    /// One GET on the live URL with the redirect refused. Reads the status and `Location`, then
    /// cancels the task: the account allows one connection, so no stream body is ever read.
    public func probeStream(streamID: Int) async -> StreamProbe {
        let url = liveStreamURL(streamID: streamID)
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: RefuseRedirect())
            bytes.task.cancel()
            guard let http = response as? HTTPURLResponse else { return .failed(.userAgentRejected) }
            var redirect: StreamServer?
            if (300...399).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               let target = URL(string: location, relativeTo: url)?.absoluteURL,
               let host = target.host(), !host.isEmpty {
                let scheme = target.scheme?.lowercased()
                redirect = StreamServer(host: host, port: target.port ?? (scheme == "https" ? 443 : 80))
            }
            return .answered(status: http.statusCode, redirect: redirect)
        } catch let error as URLError {
            switch error.code {
            case .networkConnectionLost, .badServerResponse, .cannotParseResponse, .zeroByteResource:
                return .failed(.userAgentRejected)
            default:
                return .failed(.providerUnreachable(NetworkFailure(error.code)))
            }
        } catch {
            return .failed(.providerUnreachable(.other))
        }
    }

    private final class RefuseRedirect: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    // MARK: Requests

    /// The `player_api.php` URL. Never log it: it contains the password.
    func requestURL(action: String?, extra: [(String, String)] = []) throws -> URL {
        guard var components = URLComponents(url: credentials.server, resolvingAgainstBaseURL: false) else {
            throw XtreamError.decoding("Invalid server URL")
        }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path + "/player_api.php"

        var items: [(String, String)] = [("username", credentials.username), ("password", credentials.password)]
        if let action { items.append(("action", action)) }
        items += extra
        // Encoded by hand: URLComponents.queryItems leaves "+" and "&" alone in values.
        components.percentEncodedQuery = items
            .map { "\(Self.formEncode($0.0))=\(Self.formEncode($0.1))" }
            .joined(separator: "&")
        guard let url = components.url else { throw XtreamError.decoding("Invalid server URL") }
        return url
    }

    static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func formEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    private func fetch(action: String?, extra: [(String, String)] = []) async throws -> Data {
        var request = URLRequest(url: try requestURL(action: action, extra: extra))
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .networkConnectionLost, .badServerResponse, .cannotParseResponse, .zeroByteResource:
                throw XtreamError.emptyResponse
            default:
                throw error
            }
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw XtreamError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw XtreamError.emptyResponse }
        return data
    }

    // MARK: Decoding (internal so tests can feed fixtures)

    static func decodeAccountInfo(_ data: Data) throws -> AccountInfo {
        guard let root = try Lenient.parse(data) as? [String: Any] else {
            throw XtreamError.decoding("Expected an object")
        }
        guard let user = root["user_info"] as? [String: Any], let auth = Lenient.int(user["auth"]), auth != 0 else {
            throw XtreamError.notAuthenticated
        }
        let server = root["server_info"] as? [String: Any]
        let formats = (user["allowed_output_formats"] as? [Any])?.compactMap { Lenient.string($0) } ?? []
        let expires = Lenient.date(unixSeconds: user["exp_date"]).flatMap { $0.timeIntervalSince1970 > 0 ? $0 : nil }
        return AccountInfo(
            isAuthenticated: true,
            status: Lenient.string(user["status"]) ?? "",
            expiresAt: expires,
            maxConnections: Lenient.int(user["max_connections"]) ?? 1,
            activeConnections: Lenient.int(user["active_cons"]) ?? 0,
            allowedOutputFormats: formats,
            serverTimezone: Lenient.nonEmptyString(server?["timezone"])
        )
    }

    static func decodeLiveCategories(_ data: Data) throws -> [LiveCategory] {
        guard let rows = try Lenient.parse(data) as? [Any] else { throw XtreamError.decoding("Expected an array") }
        return rows.compactMap { row in
            guard let dict = row as? [String: Any],
                  let id = Lenient.nonEmptyString(dict["category_id"]),
                  let name = Lenient.string(dict["category_name"])
            else { return nil }
            return LiveCategory(id: id, name: name)
        }
    }

    static func decodeLiveStreams(_ data: Data) throws -> [LiveStream] {
        guard let rows = try Lenient.parse(data) as? [Any] else { throw XtreamError.decoding("Expected an array") }
        return rows.compactMap { row in
            guard let dict = row as? [String: Any],
                  let id = Lenient.int(dict["stream_id"]),
                  let name = Lenient.string(dict["name"]),
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return LiveStream(
                id: id,
                number: Lenient.int(dict["num"]) ?? 0,
                name: name,
                categoryID: Lenient.nonEmptyString(dict["category_id"]),
                iconURL: Lenient.url(dict["stream_icon"]),
                epgChannelID: Lenient.nonEmptyString(dict["epg_channel_id"])
            )
        }
    }

    static func decodeShortEPG(_ data: Data) throws -> [EPGEntry] {
        let root = try Lenient.parse(data)
        let rows: [Any]
        if let dict = root as? [String: Any] {
            rows = dict["epg_listings"] as? [Any] ?? []
        } else if let array = root as? [Any] {
            rows = array
        } else {
            throw XtreamError.decoding("Expected an object")
        }
        return rows.compactMap { row -> EPGEntry? in
            guard let dict = row as? [String: Any],
                  let start = Lenient.date(unixSeconds: dict["start_timestamp"]),
                  let end = Lenient.date(unixSeconds: dict["stop_timestamp"])
            else { return nil }
            return EPGEntry(
                title: decodeBase64Text(Lenient.string(dict["title"])),
                description: decodeBase64Text(Lenient.string(dict["description"])),
                start: start,
                end: end
            )
        }
        .sorted { $0.start < $1.start }
    }

    /// EPG text is base64 UTF-8; if it isn't valid base64 text, keep the raw string.
    static func decodeBase64Text(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        guard let data = Data(base64Encoded: raw), let text = String(data: data, encoding: .utf8) else { return raw }
        return text
    }
}

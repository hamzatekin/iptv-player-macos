import Foundation

/// Login for an Xtream Codes server. `server` is scheme + host + port, e.g. `http://example.com:8080`.
public struct XtreamCredentials: Codable, Equatable, Sendable {
    public var server: URL
    public var username: String
    public var password: String

    public init(server: URL, username: String, password: String) {
        self.server = server
        self.username = username
        self.password = password
    }

    /// Same server and username: a new password is still the same account, with the same channels.
    public func isSameAccount(as other: XtreamCredentials) -> Bool {
        server == other.server && username == other.username
    }
}

/// `user_info` + `server_info` from `player_api.php` with no action.
public struct AccountInfo: Equatable, Sendable {
    public var isAuthenticated: Bool
    public var status: String
    public var expiresAt: Date?
    public var maxConnections: Int
    public var activeConnections: Int
    public var allowedOutputFormats: [String]
    public var serverTimezone: String?

    public init(
        isAuthenticated: Bool,
        status: String,
        expiresAt: Date?,
        maxConnections: Int,
        activeConnections: Int,
        allowedOutputFormats: [String],
        serverTimezone: String?
    ) {
        self.isAuthenticated = isAuthenticated
        self.status = status
        self.expiresAt = expiresAt
        self.maxConnections = maxConnections
        self.activeConnections = activeConnections
        self.allowedOutputFormats = allowedOutputFormats
        self.serverTimezone = serverTimezone
    }
}

public struct LiveCategory: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// One row of `get_live_streams`: a single playable stream.
public struct LiveStream: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let number: Int
    public let name: String
    public let categoryID: String?
    public let iconURL: URL?
    public let epgChannelID: String?

    public init(id: Int, number: Int, name: String, categoryID: String?, iconURL: URL?, epgChannelID: String?) {
        self.id = id
        self.number = number
        self.name = name
        self.categoryID = categoryID
        self.iconURL = iconURL
        self.epgChannelID = epgChannelID
    }
}

/// Quality token parsed from a stream name. Declaration order is the default-variant preference:
/// FHD first, 4K/UHD last, after streams with no token (4K is deferred for now, so it is the
/// default only when a channel has nothing else).
public enum Quality: Int, Comparable, Codable, Sendable, CaseIterable {
    case fhd, hd, sd, raw, hevc, unknown, uhd

    public static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One stream of a channel, e.g. the "FHD" or "HD PLATIN" version of "beIN SPORTS 1".
public struct ChannelVariant: Identifiable, Hashable, Sendable {
    public var id: Int { stream.id }
    public let stream: LiveStream
    public let quality: Quality
    /// What the name says after the base name, e.g. "FHD", "SD | Mobil". Empty when the name has no quality token.
    public let label: String

    public init(stream: LiveStream, quality: Quality, label: String) {
        self.stream = stream
        self.quality = quality
        self.label = label
    }
}

/// Streams that are the same channel in different qualities, merged into one row.
public struct Channel: Identifiable, Hashable, Sendable {
    /// Stable key, used for favorites and "last watched": "<categoryID>/<normalized base name>".
    public let id: String
    public let name: String
    public let categoryID: String?
    /// Lowest `num` among the variants, used for ordering.
    public let number: Int
    public let iconURL: URL?
    /// Never empty. Sorted so the default variant comes first.
    public let variants: [ChannelVariant]

    public var defaultVariant: ChannelVariant { variants[0] }
    /// True when any variant has an EPG id, so now/next can be looked up.
    public var hasGuide: Bool { variants.contains { $0.stream.epgChannelID?.isEmpty == false } }

    public init(id: String, name: String, categoryID: String?, number: Int, iconURL: URL?, variants: [ChannelVariant]) {
        precondition(!variants.isEmpty, "A channel needs at least one variant")
        self.id = id
        self.name = name
        self.categoryID = categoryID
        self.number = number
        self.iconURL = iconURL
        self.variants = variants
    }
}

/// One programme from `get_short_epg`. Title and description are already base64-decoded.
public struct EPGEntry: Hashable, Sendable {
    public let title: String
    public let description: String
    public let start: Date
    public let end: Date

    public init(title: String, description: String, start: Date, end: Date) {
        self.title = title
        self.description = description
        self.start = start
        self.end = end
    }
}

/// The live catalog as cached on disk.
public struct Catalog: Codable, Equatable, Sendable {
    public var categories: [LiveCategory]
    public var streams: [LiveStream]
    public var fetchedAt: Date

    public init(categories: [LiveCategory], streams: [LiveStream], fetchedAt: Date) {
        self.categories = categories
        self.streams = streams
        self.fetchedAt = fetchedAt
    }
}

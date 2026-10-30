import Foundation
import Security
import Synchronization

/// Keeps the last downloaded catalog on disk so the app opens instantly.
public final class CatalogCache: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appending(path: "catalog.json")
    }

    public func load() -> Catalog? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }

    public func save(_ catalog: Catalog) throws {
        let data = try JSONEncoder().encode(catalog)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    public static func isStale(_ catalog: Catalog, now: Date = .now, maxAge: TimeInterval = 24 * 60 * 60) -> Bool {
        now.timeIntervalSince(catalog.fetchedAt) > maxAge
    }
}

/// Favorites and the last watched channel, stored in UserDefaults. Keys are `Channel.id`.
public final class UserLibrary: @unchecked Sendable {
    private let defaults: UserDefaults

    private enum Key {
        static let favorites = "favoriteChannelIDs"
        static let lastChannel = "lastChannelID"
        static let lastStream = "lastStreamID"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var favorites: Set<String> {
        Set(defaults.stringArray(forKey: Key.favorites) ?? [])
    }

    public func isFavorite(_ channelID: String) -> Bool {
        favorites.contains(channelID)
    }

    public func toggleFavorite(_ channelID: String) {
        var current = favorites
        if !current.insert(channelID).inserted { current.remove(channelID) }
        defaults.set(current.sorted(), forKey: Key.favorites)
    }

    public var lastChannelID: String? {
        get { defaults.string(forKey: Key.lastChannel) }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.lastChannel) } else { defaults.removeObject(forKey: Key.lastChannel) }
        }
    }

    /// The variant (stream id) last played on `lastChannelID`.
    public var lastStreamID: Int? {
        get { defaults.object(forKey: Key.lastStream) as? Int }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.lastStream) } else { defaults.removeObject(forKey: Key.lastStream) }
        }
    }
}

public protocol CredentialStore: Sendable {
    func load() -> XtreamCredentials?
    func save(_ credentials: XtreamCredentials) throws
    func delete() throws
}

/// A Keychain call failed with this `OSStatus`.
public struct KeychainError: Error, Equatable, CustomStringConvertible {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }

    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "Keychain error \(status): \(message)"
    }
}

/// Stores the login as one generic-password Keychain item (JSON-encoded credentials).
///
/// Uses the file-based login keychain (no `kSecUseDataProtectionKeychain`): the app is ad-hoc
/// signed, and the data protection keychain would fail with -34018.
public struct KeychainCredentialStore: CredentialStore {
    public let service: String

    public init(service: String = "app.iptvplayer.mac.xtream") {
        self.service = service
    }

    private var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
        ]
    }

    public func load() -> XtreamCredentials? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(XtreamCredentials.self, from: data)
    }

    public func save(_ credentials: XtreamCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(identity as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = identity
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete() throws {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// Thread-safe in-memory store, for tests and SwiftUI previews.
public final class InMemoryCredentialStore: CredentialStore {
    private let value: Mutex<XtreamCredentials?>

    public init(_ credentials: XtreamCredentials? = nil) {
        value = Mutex(credentials)
    }

    public func load() -> XtreamCredentials? { value.withLock { $0 } }
    public func save(_ credentials: XtreamCredentials) throws { value.withLock { $0 = credentials } }
    public func delete() throws { value.withLock { $0 = nil } }
}

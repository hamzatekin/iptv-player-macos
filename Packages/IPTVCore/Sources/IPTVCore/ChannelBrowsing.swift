import Foundation

/// What the sidebar has selected. The raw value is stable text so it can live in `@AppStorage`.
public enum SidebarSelection: Hashable, Sendable, RawRepresentable {
    case favorites
    case all
    case category(String)

    private static let categoryPrefix = "category:"

    public init?(rawValue: String) {
        switch rawValue {
        case "favorites": self = .favorites
        case "all": self = .all
        case let value where value.hasPrefix(Self.categoryPrefix):
            self = .category(String(value.dropFirst(Self.categoryPrefix.count)))
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .favorites: "favorites"
        case .all: "all"
        case .category(let id): Self.categoryPrefix + id
        }
    }
}

/// Pure list logic for the channel list: filtering, search, up/down neighbours.
public enum ChannelBrowsing {
    /// Case- and diacritic-insensitive text, with the Turkish dotless "ı" treated as "i".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ı", with: "i")
    }

    /// A non-empty search spans all channels whatever the sidebar selection is.
    public static func visibleChannels(
        _ channels: [Channel],
        selection: SidebarSelection,
        favorites: Set<String>,
        search: String
    ) -> [Channel] {
        let query = fold(search.trimmingCharacters(in: .whitespacesAndNewlines))
        if !query.isEmpty {
            return channels.filter { fold($0.name).contains(query) }
        }
        switch selection {
        case .all: return channels
        case .favorites: return channels.filter { favorites.contains($0.id) }
        case .category(let id): return channels.filter { $0.categoryID == id }
        }
    }

    /// The channel after (`step` = 1) or before (`step` = -1) `currentID`, wrapping around.
    /// When `currentID` isn't in the list, returns the first channel.
    public static func neighbour(of currentID: String?, in channels: [Channel], step: Int) -> Channel? {
        guard !channels.isEmpty else { return nil }
        guard let currentID, let index = channels.firstIndex(where: { $0.id == currentID }) else {
            return channels[0]
        }
        let count = channels.count
        return channels[((index + step) % count + count) % count]
    }
}

/// Now/next for one channel at a moment in time.
public struct NowNext: Equatable, Sendable {
    public let now: EPGEntry?
    public let next: EPGEntry?

    public init(now: EPGEntry?, next: EPGEntry?) {
        self.now = now
        self.next = next
    }

    /// Entries may arrive in any order. `now` has `start <= date < end`; `next` is the first entry
    /// starting at or after the end of `now` (or after `date` when nothing is on now).
    public init(entries: [EPGEntry], at date: Date) {
        let sorted = entries.sorted { $0.start < $1.start }
        let now = sorted.first { $0.start <= date && date < $0.end }
        let threshold = now?.end
        self.now = now
        self.next = sorted.first { entry in
            if let threshold { return entry.start >= threshold }
            return entry.start > date
        }
    }

    /// How far into the current programme `date` is, from 0 to 1. Nil when nothing is on now.
    public func progress(at date: Date) -> Double? {
        guard let now else { return nil }
        let length = now.end.timeIntervalSince(now.start)
        guard length > 0 else { return nil }
        return min(max(date.timeIntervalSince(now.start) / length, 0), 1)
    }
}

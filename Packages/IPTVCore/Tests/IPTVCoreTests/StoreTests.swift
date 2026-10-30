import Foundation
import Testing
@testable import IPTVCore

@Suite struct StoreTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "iptvcore-tests-\(UUID().uuidString)")
    }

    private let sample = Catalog(
        categories: [LiveCategory(id: "1", name: "News")],
        streams: [stream(1, 1, "News HD", icon: "http://example.com/n.png", epg: "news.tr")],
        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    @Test func cacheRoundTripCreatesDirectory() throws {
        let dir = tempDirectory().appending(path: "nested")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let cache = CatalogCache(directory: dir)
        #expect(cache.load() == nil)
        try cache.save(sample)
        #expect(cache.load() == sample)
        try cache.save(Catalog(categories: [], streams: [], fetchedAt: sample.fetchedAt))
        #expect(cache.load()?.streams.isEmpty == true)
    }

    @Test func cacheLoadReturnsNilForCorruptFile() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = CatalogCache(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cache.fileURL)
        #expect(cache.load() == nil)
    }

    @Test func staleness() {
        let fetched = sample.fetchedAt
        #expect(!CatalogCache.isStale(sample, now: fetched.addingTimeInterval(60)))
        #expect(!CatalogCache.isStale(sample, now: fetched.addingTimeInterval(24 * 3600)))
        #expect(CatalogCache.isStale(sample, now: fetched.addingTimeInterval(24 * 3600 + 1)))
        #expect(CatalogCache.isStale(sample, now: fetched.addingTimeInterval(120), maxAge: 60))
    }

    private func freshDefaults() -> (UserDefaults, String) {
        let name = UUID().uuidString
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func favoritesToggleAndPersist() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let library = UserLibrary(defaults: defaults)
        #expect(library.favorites.isEmpty)
        library.toggleFavorite("597/trt 1")
        library.toggleFavorite("685/bein sports 1")
        #expect(library.isFavorite("597/trt 1"))
        #expect(UserLibrary(defaults: defaults).favorites == ["597/trt 1", "685/bein sports 1"])
        library.toggleFavorite("597/trt 1")
        #expect(!library.isFavorite("597/trt 1"))
        #expect(defaults.stringArray(forKey: "favoriteChannelIDs") == ["685/bein sports 1"])
    }

    @Test func lastChannelAndStreamPersistAndClear() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let library = UserLibrary(defaults: defaults)
        #expect(library.lastChannelID == nil)
        #expect(library.lastStreamID == nil)
        library.lastChannelID = "597/trt 1"
        library.lastStreamID = 149301
        let reopened = UserLibrary(defaults: defaults)
        #expect(reopened.lastChannelID == "597/trt 1")
        #expect(reopened.lastStreamID == 149301)
        #expect(defaults.string(forKey: "lastChannelID") == "597/trt 1")
        #expect(defaults.integer(forKey: "lastStreamID") == 149301)
        library.lastChannelID = nil
        library.lastStreamID = nil
        #expect(defaults.object(forKey: "lastChannelID") == nil)
        #expect(defaults.object(forKey: "lastStreamID") == nil)
    }

    @Test func inMemoryCredentialStore() throws {
        let store = InMemoryCredentialStore()
        let credentials = XtreamCredentials(server: URL(string: "http://example.com:8080")!, username: "u", password: "p")
        #expect(store.load() == nil)
        try store.save(credentials)
        #expect(store.load() == credentials)
        try store.delete()
        #expect(store.load() == nil)
    }
}

import Foundation
import IPTVCore
import Observation

/// What the root view shows.
enum AppPhase {
    case login
    /// Signed in, no catalog yet (first run, or the cache is gone).
    case loading
    case ready
}

struct CategoryRow: Identifiable {
    let category: LiveCategory
    let count: Int
    var id: String { category.id }
}

/// A play request waiting for the user to confirm that the one connection may be taken over.
struct PendingPlay {
    let channel: Channel
    let variant: ChannelVariant
}

@MainActor
@Observable
final class AppModel {
    // MARK: State

    private(set) var phase = AppPhase.login
    private(set) var credentials: XtreamCredentials?

    private(set) var loginError: String?
    private(set) var isSigningIn = false

    private(set) var catalog: Catalog?
    private(set) var channels: [Channel] = []
    private(set) var categoryRows: [CategoryRow] = []
    private(set) var favorites: Set<String> = []
    private(set) var isRefreshing = false
    /// Shown instead of the channel list when the first load fails.
    private(set) var loadError: String?
    /// Small non-blocking note, e.g. a failed background refresh.
    private(set) var notice: String?

    private(set) var selection = SidebarSelection.all
    var searchText = ""
    /// The highlighted row in the channel list.
    var selectedChannelID: String?

    private(set) var playingChannelID: String?
    private(set) var playingStreamID: Int?
    var pendingPlay: PendingPlay?
    /// Why the current stream failed, once the checks after a failure have finished.
    private(set) var playbackProblem: ProviderProblem?
    private(set) var isDiagnosing = false

    private(set) var epgCache: [Int: EPGCacheEntry] = [:]

    struct EPGCacheEntry {
        let entries: [EPGEntry]
        let fetchedAt: Date
        let succeeded: Bool

        var ttl: TimeInterval { succeeded ? 10 * 60 : 60 }
    }

    // MARK: Collaborators

    let player: MPVPlayer
    let window = WindowState()
    let library = UserLibrary()
    @ObservationIgnored private let credentialStore: any CredentialStore
    @ObservationIgnored private let cache: CatalogCache
    @ObservationIgnored private var client: XtreamClient?
    @ObservationIgnored private var channelsByID: [String: Channel] = [:]
    @ObservationIgnored private var started = false
    /// Bumped by each refresh and by sign-out, so a refresh that sign-out overtook changes nothing.
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var diagnosisTask: Task<Void, Never>?
    @ObservationIgnored private var guideTimer: Task<Void, Never>?
    @ObservationIgnored private var epgQueue: [Int] = []
    @ObservationIgnored private var epgInFlight = Set<Int>()

    private static let selectionKey = "sidebarSelection"
    private static let maxEPGRequests = 4
    private static let maxQueuedEPG = 30

    init() {
        player = MPVPlayer(userAgent: AppSettings.userAgent)
        credentialStore = KeychainCredentialStore()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cache = CatalogCache(directory: support.appending(path: "IPTVPlayer"))
        favorites = library.favorites
        selection = UserDefaults.standard.string(forKey: Self.selectionKey).flatMap(SidebarSelection.init) ?? .all
        player.onFailure = { [weak self] in self?.diagnosePlaybackFailure() }
    }

    // MARK: Launch

    func start() {
        guard !started else { return }
        started = true
        guideTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.refreshPlayingGuide()
            }
        }
        #if DEBUG
        // Plays a stream that isn't the provider's (e.g. Apple's test stream), so player changes can be
        // checked without using the account's one connection.
        if let url = ProcessInfo.processInfo.environment["IPTV_DEBUG_PLAY_URL"].flatMap(URL.init(string:)) {
            player.play(url)
        }
        #endif
        guard let credentials = launchCredentials() else { return }
        useCredentials(credentials)
        if let cached = cache.load() {
            apply(cached)
            phase = .ready
            if CatalogCache.isStale(cached) { Task { await refresh() } }
        } else {
            phase = .loading
            Task { await refresh() }
        }
    }

    private func launchCredentials() -> XtreamCredentials? {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let server = env["IPTV_SERVER"].flatMap(ServerAddress.normalize),
           let username = env["IPTV_USERNAME"], !username.isEmpty,
           let password = env["IPTV_PASSWORD"], !password.isEmpty {
            return XtreamCredentials(server: server, username: username, password: password)
        }
        #endif
        return credentialStore.load()
    }

    private func useCredentials(_ credentials: XtreamCredentials) {
        self.credentials = credentials
        client = XtreamClient(credentials: credentials, userAgent: AppSettings.userAgent)
        player.logSecrets = [credentials.username, credentials.password]
    }

    // MARK: Sign in and out

    func signIn(server: String, username: String, password: String) async {
        guard !isSigningIn else { return }
        guard let url = ServerAddress.normalize(server) else {
            loginError = "Enter a valid server address."
            return
        }
        let credentials = XtreamCredentials(
            server: url, username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password
        )
        isSigningIn = true
        loginError = nil
        defer { isSigningIn = false }
        do {
            _ = try await XtreamClient(credentials: credentials, userAgent: AppSettings.userAgent).accountInfo()
        } catch {
            loginError = Self.message(for: error)
            return
        }
        notice = nil
        do {
            try credentialStore.save(credentials)
        } catch {
            notice = "Couldn't save the login to the Keychain. You will need to sign in again next time."
        }
        useCredentials(credentials)
        loadError = nil
        phase = .loading
        await refresh()
    }

    func signOut() {
        stop()
        playTask?.cancel()
        pendingPlay = nil
        try? credentialStore.delete()
        try? FileManager.default.removeItem(at: cache.fileURL)
        // Builds before XtreamClient.defaultSession cached API responses here, keyed by URLs that
        // contain the password. Only channel logos are cached here now.
        URLCache.shared.removeAllCachedResponses()
        refreshGeneration += 1
        isRefreshing = false
        credentials = nil
        client = nil
        catalog = nil
        channels = []
        channelsByID = [:]
        categoryRows = []
        epgCache = [:]
        epgQueue = []
        selectedChannelID = nil
        searchText = ""
        loadError = nil
        notice = nil
        loginError = nil
        phase = .login
    }

    // MARK: Catalog

    /// Downloads categories and streams. With a catalog on screen a failure is only a notice.
    func refresh() async {
        guard let client, !isRefreshing else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        defer { if generation == refreshGeneration { isRefreshing = false } }
        do {
            let categories = try await client.liveCategories()
            let streams = try await client.liveStreams()
            guard generation == refreshGeneration else { return }
            let fresh = Catalog(categories: categories, streams: streams, fetchedAt: .now)
            try? cache.save(fresh)
            apply(fresh)
            loadError = nil
            notice = nil
            phase = .ready
        } catch {
            guard generation == refreshGeneration else { return }
            let text = Self.message(for: error)
            if catalog == nil {
                loadError = text
            } else {
                notice = "Couldn't refresh channels. " + text
            }
        }
    }

    private func apply(_ catalog: Catalog) {
        self.catalog = catalog
        channels = ChannelGrouping.group(catalog.streams)
        channelsByID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let counts = Dictionary(grouping: channels, by: \.categoryID).mapValues(\.count)
        categoryRows = catalog.categories.compactMap { category in
            counts[category.id].map { CategoryRow(category: category, count: $0) }
        }
        if case .category(let id) = selection, !categoryRows.contains(where: { $0.id == id }) {
            select(.all)
        }
        if selectedChannelID == nil || channelsByID[selectedChannelID ?? ""] == nil {
            selectedChannelID = library.lastChannelID.flatMap { channelsByID[$0] }?.id
        }
    }

    func select(_ selection: SidebarSelection) {
        self.selection = selection
        UserDefaults.standard.set(selection.rawValue, forKey: Self.selectionKey)
    }

    // MARK: Lists

    var visibleChannels: [Channel] {
        ChannelBrowsing.visibleChannels(channels, selection: selection, favorites: favorites, search: searchText)
    }

    var favoritesCount: Int { channels.count { favorites.contains($0.id) } }

    var listTitle: String {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "Search" }
        switch selection {
        case .favorites: return "Favorites"
        case .all: return "All Channels"
        case .category(let id): return categoryRows.first { $0.id == id }?.category.name ?? "Channels"
        }
    }

    func channel(id: String?) -> Channel? { id.flatMap { channelsByID[$0] } }

    var playingChannel: Channel? { channel(id: playingChannelID) }

    func isFavorite(_ channel: Channel) -> Bool { favorites.contains(channel.id) }

    func toggleFavorite(_ channel: Channel) {
        library.toggleFavorite(channel.id)
        favorites = library.favorites
    }

    /// The command-menu target: the highlighted row, else what is playing.
    func toggleFavoriteOfCurrent() {
        if let channel = channel(id: selectedChannelID) ?? playingChannel { toggleFavorite(channel) }
    }

    // MARK: Playback

    func play(_ channel: Channel, variant: ChannelVariant? = nil) {
        guard let client else { return }
        let variant = variant ?? rememberedVariant(for: channel)
        selectedChannelID = channel.id
        playTask?.cancel()
        playTask = Task {
            // Starting from nothing: make sure we don't kick someone else off the one connection.
            switch player.state {
            case .idle, .failed:
                if let info = try? await client.accountInfo(), info.activeConnections >= info.maxConnections {
                    guard !Task.isCancelled else { return }
                    pendingPlay = PendingPlay(channel: channel, variant: variant)
                    return
                }
            case .loading, .playing:
                break
            }
            guard !Task.isCancelled else { return }
            begin(channel, variant)
        }
    }

    func confirmPendingPlay() {
        guard let pending = pendingPlay else { return }
        pendingPlay = nil
        begin(pending.channel, pending.variant)
    }

    private func begin(_ channel: Channel, _ variant: ChannelVariant) {
        guard let client else { return }
        clearDiagnosis()
        player.play(client.liveStreamURL(streamID: variant.stream.id))
        playingChannelID = channel.id
        playingStreamID = variant.stream.id
        library.lastChannelID = channel.id
        library.lastStreamID = variant.stream.id
        requestNowNext(for: channel)
    }

    private func rememberedVariant(for channel: Channel) -> ChannelVariant {
        guard library.lastChannelID == channel.id, let streamID = library.lastStreamID,
              let variant = channel.variants.first(where: { $0.stream.id == streamID })
        else { return channel.defaultVariant }
        return variant
    }

    /// Replays the current channel and variant, e.g. after a failure.
    func retry() {
        guard let channel = playingChannel else { return }
        play(channel, variant: channel.variants.first { $0.stream.id == playingStreamID })
    }

    func stop() {
        playTask?.cancel()
        clearDiagnosis()
        player.stop()
        playingChannelID = nil
        playingStreamID = nil
    }

    /// mpv only says "loading failed", so ask the provider what went wrong. Runs after the failed
    /// stream has closed, so it never competes with it for the one connection.
    private func diagnosePlaybackFailure() {
        guard let client, let streamID = playingStreamID else { return }
        clearDiagnosis()
        isDiagnosing = true
        diagnosisTask = Task {
            let recentlyPlayed = player.lastPlayedAt.map { Date.now.timeIntervalSince($0) < 10 * 60 } ?? false
            let problem = await PlaybackDiagnosis.run(client: client, streamID: streamID, recentlyPlayed: recentlyPlayed)
            guard !Task.isCancelled else { return }
            playbackProblem = problem
            isDiagnosing = false
        }
    }

    /// Cancelling also stops the checks' requests, so a new stream doesn't share the connection with them.
    private func clearDiagnosis() {
        diagnosisTask?.cancel()
        diagnosisTask = nil
        playbackProblem = nil
        isDiagnosing = false
    }

    func step(_ direction: Int) {
        let current = playingChannelID ?? selectedChannelID
        if let next = ChannelBrowsing.neighbour(of: current, in: visibleChannels, step: direction) { play(next) }
    }

    func changeVolume(by delta: Double) { player.setVolume(player.volume + delta) }

    func userAgentChanged() {
        let userAgent = AppSettings.userAgent
        player.setUserAgent(userAgent)
        if let credentials { client = XtreamClient(credentials: credentials, userAgent: userAgent) }
    }

    func loadAccountInfo() async throws -> AccountInfo {
        guard let client else { throw XtreamError.notAuthenticated }
        return try await client.accountInfo()
    }

    // MARK: Now and next

    func nowNext(for channel: Channel, at date: Date = .now) -> NowNext? {
        guard let streamID = guideStreamID(channel), let cached = epgCache[streamID], !cached.entries.isEmpty else { return nil }
        return NowNext(entries: cached.entries, at: date)
    }

    private func guideStreamID(_ channel: Channel) -> Int? {
        channel.variants.first { $0.stream.epgChannelID?.isEmpty == false }?.stream.id
    }

    /// Rows call this when they appear. Cached for 10 minutes; at most 4 requests run at once.
    func requestNowNext(for channel: Channel) {
        guard client != nil, channel.hasGuide, let streamID = guideStreamID(channel) else { return }
        if let cached = epgCache[streamID], Date.now.timeIntervalSince(cached.fetchedAt) < cached.ttl { return }
        guard !epgInFlight.contains(streamID), !epgQueue.contains(streamID) else { return }
        epgQueue.append(streamID)
        if epgQueue.count > Self.maxQueuedEPG { epgQueue.removeFirst() }
        pumpEPG()
    }

    private func refreshPlayingGuide() {
        if let channel = playingChannel { requestNowNext(for: channel) }
    }

    /// Newest requests first: the rows that just scrolled into view matter most.
    private func pumpEPG() {
        while epgInFlight.count < Self.maxEPGRequests, let client, let streamID = epgQueue.popLast() {
            epgInFlight.insert(streamID)
            Task {
                let entries = try? await client.shortEPG(streamID: streamID, limit: 4)
                epgInFlight.remove(streamID)
                if self.client?.credentials == client.credentials {
                    epgCache[streamID] = EPGCacheEntry(entries: entries ?? [], fetchedAt: .now, succeeded: entries != nil)
                }
                pumpEPG()
            }
        }
    }

    // MARK: Errors

    static func message(for error: Error) -> String {
        ProviderProblem(error: error).detail
    }
}

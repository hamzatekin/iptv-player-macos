import Foundation
import Testing
@testable import IPTVCore

@Suite struct BrowsingTests {
    private func channel(_ id: String, _ name: String, category: String) -> Channel {
        let s = LiveStream(id: id.hashValue, number: 0, name: name, categoryID: category, iconURL: nil, epgChannelID: nil)
        return Channel(
            id: id, name: name, categoryID: category, number: 0, iconURL: nil,
            variants: [ChannelVariant(stream: s, quality: .hd, label: "HD")]
        )
    }

    private var channels: [Channel] {
        [
            channel("a/trt haber", "TRT HABER", category: "a"),
            channel("a/trt 1", "TRT 1", category: "a"),
            channel("b/atv", "ATV", category: "b"),
            channel("b/türk", "TÜRK", category: "b"),
            channel("c/kanal", "KANAL I", category: "c"),
        ]
    }

    private func ids(_ list: [Channel]) -> [String] { list.map(\.id) }

    @Test func selections() {
        let favorites: Set<String> = ["b/atv", "gone"]
        #expect(ids(ChannelBrowsing.visibleChannels(channels, selection: .all, favorites: favorites, search: "")).count == 5)
        #expect(ids(ChannelBrowsing.visibleChannels(channels, selection: .favorites, favorites: favorites, search: "")) == ["b/atv"])
        #expect(ids(ChannelBrowsing.visibleChannels(channels, selection: .category("a"), favorites: favorites, search: "")) == ["a/trt haber", "a/trt 1"])
        #expect(ChannelBrowsing.visibleChannels(channels, selection: .category("zzz"), favorites: [], search: "").isEmpty)
    }

    @Test func searchSpansAllChannelsAndIgnoresSelection() {
        let result = ChannelBrowsing.visibleChannels(channels, selection: .favorites, favorites: [], search: "trt")
        #expect(ids(result) == ["a/trt haber", "a/trt 1"])
    }

    @Test(arguments: [
        ("trt haber", ["a/trt haber"]),
        ("TRT HABER", ["a/trt haber"]),
        ("turk", ["b/türk"]),
        ("TÜRK", ["b/türk"]),
        ("kanal ı", ["c/kanal"]),
        ("kanal i", ["c/kanal"]),
        ("  atv  ", ["b/atv"]),
        ("nothing", []),
    ])
    func searchMatching(query: String, expected: [String]) {
        #expect(ids(ChannelBrowsing.visibleChannels(channels, selection: .all, favorites: [], search: query)) == expected)
    }

    @Test func whitespaceOnlySearchIsNoSearch() {
        #expect(ChannelBrowsing.visibleChannels(channels, selection: .category("c"), favorites: [], search: "   ").count == 1)
    }

    @Test func neighbourWrapsAndHandlesMissing() {
        #expect(ChannelBrowsing.neighbour(of: "a/trt haber", in: channels, step: 1)?.id == "a/trt 1")
        #expect(ChannelBrowsing.neighbour(of: "c/kanal", in: channels, step: 1)?.id == "a/trt haber")
        #expect(ChannelBrowsing.neighbour(of: "a/trt haber", in: channels, step: -1)?.id == "c/kanal")
        #expect(ChannelBrowsing.neighbour(of: "missing", in: channels, step: -1)?.id == "a/trt haber")
        #expect(ChannelBrowsing.neighbour(of: nil, in: channels, step: 1)?.id == "a/trt haber")
        #expect(ChannelBrowsing.neighbour(of: "x", in: [], step: 1) == nil)
    }

    @Test func selectionRawValueRoundTrips() {
        for selection in [SidebarSelection.favorites, .all, .category("597"), .category("a:b")] {
            #expect(SidebarSelection(rawValue: selection.rawValue) == selection)
        }
        #expect(SidebarSelection(rawValue: "junk") == nil)
    }

    // MARK: Now/next

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func entry(_ title: String, _ start: TimeInterval, _ end: TimeInterval) -> EPGEntry {
        EPGEntry(title: title, description: "", start: t0.addingTimeInterval(start), end: t0.addingTimeInterval(end))
    }

    @Test func nowAndNext() {
        let entries = [entry("C", 200, 300), entry("A", 0, 100), entry("B", 100, 200)]
        let result = NowNext(entries: entries, at: t0.addingTimeInterval(150))
        #expect(result.now?.title == "B")
        #expect(result.next?.title == "C")
        #expect(result.progress(at: t0.addingTimeInterval(150)) == 0.5)
    }

    @Test func boundariesAreStartInclusiveEndExclusive() {
        let entries = [entry("A", 0, 100), entry("B", 100, 200)]
        #expect(NowNext(entries: entries, at: t0).now?.title == "A")
        #expect(NowNext(entries: entries, at: t0.addingTimeInterval(100)).now?.title == "B")
        #expect(NowNext(entries: entries, at: t0.addingTimeInterval(200)).now == nil)
    }

    @Test func gapAfterNowSkipsToLaterEntry() {
        let entries = [entry("A", 0, 100), entry("C", 150, 250)]
        let result = NowNext(entries: entries, at: t0.addingTimeInterval(50))
        #expect(result.next?.title == "C")
    }

    @Test func noNowUsesFirstEntryAfterDate() {
        let entries = [entry("A", 0, 100), entry("B", 200, 300), entry("C", 300, 400)]
        let result = NowNext(entries: entries, at: t0.addingTimeInterval(150))
        #expect(result.now == nil)
        #expect(result.next?.title == "B")
        #expect(result.progress(at: t0.addingTimeInterval(150)) == nil)
    }

    @Test func emptyEntries() {
        let result = NowNext(entries: [], at: t0)
        #expect(result == NowNext(now: nil, next: nil))
    }

    @Test func progressIsClamped() {
        let result = NowNext(now: entry("A", 0, 100), next: nil)
        #expect(result.progress(at: t0.addingTimeInterval(-10)) == 0)
        #expect(result.progress(at: t0.addingTimeInterval(500)) == 1)
    }
}

import Foundation
import Testing
@testable import IPTVCore

@Suite struct GroupingTests {
    @Test(arguments: [
        ("∞∞∞ TURK ULUSAL ∞∞∞", true),
        ("### TURK YEREL ###", true),
        ("EXXEN INT  |  ", true),
        ("24/7 Katarsis", false),
        ("beIN SPORTS 1 SD | Mobil", false),
        ("A HABER", false),
        ("tabii TV HD", false),
        ("+ Single", false),
        ("", true),
    ])
    func separators(name: String, expected: Bool) {
        #expect(ChannelGrouping.isSeparator(name) == expected)
    }

    @Test(arguments: [
        ("TRT 1 HD", "TRT 1", Quality.hd, "HD"),
        ("TRT 1 FHD", "TRT 1", .fhd, "FHD"),
        ("TRT 1  HEVC", "TRT 1", .hevc, "HEVC"),
        ("TRT 4K", "TRT", .uhd, "4K"),
        ("tabii SPOR UHD", "tabii SPOR", .uhd, "UHD"),
        ("S SPORT RAW", "S SPORT", .raw, "RAW"),
        ("show h265", "show", .hevc, "h265"),
        ("beIN SPORTS 1 SD | Mobil", "beIN SPORTS 1", .sd, "SD | Mobil"),
        ("beIN SPORTS 1 SD+", "beIN SPORTS 1", .sd, "SD+"),
        ("beIN SPORTS 1 HD PLATIN", "beIN SPORTS 1", .hd, "HD PLATIN"),
        ("beIN SPORTS 1 HD TICARI | Mac Saati", "beIN SPORTS 1", .hd, "HD TICARI | Mac Saati"),
        ("EXXEN SPORT 1 SD  | Mac Saati", "EXXEN SPORT 1", .sd, "SD | Mac Saati"),
        ("ATV EURO", "ATV EURO", .unknown, ""),
        ("HD Movies", "HD Movies", .unknown, ""),
        ("HDTV Plus", "HDTV Plus", .unknown, ""),
        ("  A   HABER ", "A HABER", .unknown, ""),
    ])
    func parsing(name: String, base: String, quality: Quality, label: String) {
        let parsed = ChannelGrouping.parse(name)
        #expect(parsed.base == base)
        #expect(parsed.quality == quality)
        #expect(parsed.label == label)
    }

    private func groupedFixture() throws -> [Channel] {
        ChannelGrouping.group(try XtreamClient.decodeLiveStreams(fixture("live_streams")))
    }

    @Test func separatorsAreDropped() throws {
        let channels = try groupedFixture()
        #expect(!channels.contains { ChannelGrouping.isSeparator($0.name) })
        #expect(!channels.flatMap(\.variants).contains { ChannelGrouping.isSeparator($0.stream.name) })
    }

    @Test func channelsAreOrderedByNumber() throws {
        let numbers = try groupedFixture().map(\.number)
        #expect(numbers == numbers.sorted())
    }

    @Test func trt1MergesAndDefaultsToFHD() throws {
        let channel = try #require(try groupedFixture().first { $0.id == "597/trt 1" })
        #expect(channel.name == "TRT 1")
        #expect(channel.number == 4)
        #expect(channel.variants.map(\.quality) == [.fhd, .hd])
        #expect(channel.defaultVariant.stream.id == 149301)
        #expect(channel.hasGuide)
        #expect(channel.iconURL != nil)
        // HEVC version lives in another category, so it is a separate channel.
        #expect(try groupedFixture().contains { $0.id == "724/trt 1" })
    }

    @Test func beinSports1VariantsAndOrder() throws {
        let channel = try #require(try groupedFixture().first { $0.id == "685/bein sports 1" })
        #expect(channel.name == "beIN SPORTS 1")
        #expect(channel.number == 87)
        #expect(channel.variants.map(\.label) == [
            "FHD", "HD", "HD PLATIN", "HD TICARI | Mac Saati", "SD+", "SD | Mobil",
        ])
        #expect(channel.defaultVariant.stream.id == 239154)
    }

    @Test func fourKIsNeverDefaultWhenOtherVariantsExist() throws {
        let tabii = try #require(try groupedFixture().first { $0.id == "1223/tabii spor" })
        #expect(tabii.variants.map(\.quality) == [.fhd, .hd, .uhd])
        let trt4k = try #require(try groupedFixture().first { $0.id == "597/trt" })
        #expect(trt4k.defaultVariant.quality == .uhd)
    }

    /// Like "NM SPORT AR EVENTS 1": a 4K stream and one with no quality in its name.
    @Test func untaggedVariantIsDefaultOver4K() {
        let channels = ChannelGrouping.group([stream(1, 1, "X UHD"), stream(2, 2, "X")])
        #expect(channels.map(\.defaultVariant.stream.id) == [2])
    }

    @Test func sameBaseInDifferentCategoriesStaysSeparate() {
        let channels = ChannelGrouping.group([
            stream(1, 1, "News HD", category: "a"),
            stream(2, 2, "News HD", category: "b"),
            stream(3, 3, "Plain", category: nil),
        ])
        #expect(channels.map(\.id) == ["a/news", "b/news", "none/plain"])
    }

    @Test func iconFallsBackToFirstNonNilIcon() {
        let channels = ChannelGrouping.group([
            stream(1, 1, "X FHD", icon: nil),
            stream(2, 2, "X HD", icon: "http://example.com/x.png"),
        ])
        #expect(channels.count == 1)
        #expect(channels[0].iconURL == URL(string: "http://example.com/x.png"))
    }
}

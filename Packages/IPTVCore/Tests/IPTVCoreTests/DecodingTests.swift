import Foundation
import Testing
@testable import IPTVCore

@Suite struct DecodingTests {
    @Test func accountInfoFixture() throws {
        let info = try XtreamClient.decodeAccountInfo(fixture("account_info"))
        #expect(info.isAuthenticated)
        #expect(info.status == "Active")
        #expect(info.maxConnections == 1)
        #expect(info.activeConnections == 0)
        #expect(info.allowedOutputFormats == ["ts"])
        #expect(info.expiresAt == Date(timeIntervalSince1970: 1867422300))
        #expect(info.serverTimezone == "Europe/Istanbul")
    }

    @Test func authFailedThrows() throws {
        let data = try fixture("account_info_auth_failed")
        #expect(throws: XtreamError.notAuthenticated) { try XtreamClient.decodeAccountInfo(data) }
    }

    @Test func missingUserInfoThrowsNotAuthenticated() {
        #expect(throws: XtreamError.notAuthenticated) { try XtreamClient.decodeAccountInfo(Data("{}".utf8)) }
    }

    @Test func accountInfoAcceptsLooseTypesAndDefaults() throws {
        let json = #"{"user_info":{"auth":"1","exp_date":null,"max_connections":3,"active_cons":2}}"#
        let info = try XtreamClient.decodeAccountInfo(Data(json.utf8))
        #expect(info.expiresAt == nil)
        #expect(info.maxConnections == 3)
        #expect(info.activeConnections == 2)
        #expect(info.allowedOutputFormats.isEmpty)
        #expect(info.serverTimezone == nil)

        let bare = try XtreamClient.decodeAccountInfo(Data(#"{"user_info":{"auth":1}}"#.utf8))
        #expect(bare.maxConnections == 1)
        #expect(bare.activeConnections == 0)
    }

    @Test func garbageIsDecodingError() {
        #expect(throws: XtreamError.self) { try XtreamClient.decodeLiveStreams(Data("<html>".utf8)) }
        #expect(throws: XtreamError.emptyResponse) { try XtreamClient.decodeLiveStreams(Data()) }
    }

    @Test func categoriesWithMixedIDTypes() throws {
        let categories = try XtreamClient.decodeLiveCategories(fixture("live_categories"))
        #expect(categories == [
            LiveCategory(id: "597", name: "TURK ULUSAL"),
            LiveCategory(id: "685", name: "BEIN SPORTS"),
            LiveCategory(id: "157", name: "TURK HABER"),
        ])
    }

    @Test func streamsFixtureDecodesAllRows() throws {
        let streams = try XtreamClient.decodeLiveStreams(fixture("live_streams"))
        #expect(streams.count == 48)
        let separator = try #require(streams.first { $0.id == 149296 })
        #expect(separator.epgChannelID == nil)
        let trt1 = try #require(streams.first { $0.id == 149300 })
        #expect(trt1.name == "TRT 1 HD")
        #expect(trt1.number == 4)
        #expect(trt1.categoryID == "597")
        #expect(trt1.epgChannelID == "trt1.tr")
        #expect(trt1.iconURL == URL(string: "https://example.com/logos/trt1.png"))
        let emptyIcon = try #require(streams.first { $0.id == 149623 })
        #expect(emptyIcon.iconURL == nil)
    }

    @Test func streamRowsWithoutIDOrNameAreSkipped() throws {
        let json = """
        [{"num":1,"name":"No ID","category_id":"1"},
         {"num":2,"stream_id":"20","category_id":"1"},
         {"num":"3","name":"Good","stream_id":"30","category_id":7,"stream_icon":"not a url","epg_channel_id":""}]
        """
        let streams = try XtreamClient.decodeLiveStreams(Data(json.utf8))
        #expect(streams.count == 1)
        #expect(streams[0].id == 30)
        #expect(streams[0].number == 3)
        #expect(streams[0].categoryID == "7")
        #expect(streams[0].iconURL == nil)
        #expect(streams[0].epgChannelID == nil)
    }

    @Test func epgFixture() throws {
        let entries = try XtreamClient.decodeShortEPG(fixture("short_epg"))
        #expect(entries.count == 2)
        #expect(entries[0].title == "Ana Haber")
        #expect(entries[0].description == "Günün önemli haberleri.")
        #expect(entries[0].start == Date(timeIntervalSince1970: 1793386800))
        #expect(entries[0].end == Date(timeIntervalSince1970: 1793390400))
        #expect(entries[1].title == "Dizi: Gönül Dağı")
        #expect(entries[1].description == "")
        #expect(entries[1].start == Date(timeIntervalSince1970: 1793390400))
        #expect(entries[1].end == Date(timeIntervalSince1970: 1793397600))
    }

    @Test func epgEmptyFixture() throws {
        #expect(try XtreamClient.decodeShortEPG(fixture("short_epg_empty")).isEmpty)
    }

    @Test func epgSortsByStartAndKeepsRawTextWhenNotBase64() throws {
        let json = """
        {"epg_listings":[
          {"title":"Not base64!","description":"","start_timestamp":200,"stop_timestamp":300},
          {"title":"QQ==","description":"","start_timestamp":"100","stop_timestamp":"200"}]}
        """
        let entries = try XtreamClient.decodeShortEPG(Data(json.utf8))
        #expect(entries.map(\.title) == ["A", "Not base64!"])
    }
}

import Foundation
import Testing
@testable import IPTVCore

@Test func liveStreamURLUsesTsPath() {
    let client = XtreamClient(
        credentials: XtreamCredentials(server: URL(string: "http://example.com:8080")!, username: "u", password: "p"),
        userAgent: "test"
    )
    #expect(client.liveStreamURL(streamID: 42).absoluteString == "http://example.com:8080/live/u/p/42.ts")
}

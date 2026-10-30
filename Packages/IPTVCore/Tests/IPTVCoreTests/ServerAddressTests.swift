import Foundation
import Testing
@testable import IPTVCore

@Suite struct ServerAddressTests {
    @Test(arguments: [
        ("http://example.com:8080", "http://example.com:8080"),
        ("example.com:8080", "http://example.com:8080"),
        ("  example.com  ", "http://example.com"),
        ("http://example.com:8080/", "http://example.com:8080"),
        ("http://example.com:8080/player_api.php?username=a", "http://example.com:8080"),
        ("https://example.com/panel/", "https://example.com"),
        ("HTTP://Example.com", "http://Example.com"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(ServerAddress.normalize(input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "ftp://example.com", "http://", "://x"])
    func rejects(input: String) {
        #expect(ServerAddress.normalize(input) == nil)
    }
}

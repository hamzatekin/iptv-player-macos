import Foundation

enum AppSettings {
    /// UserDefaults key for the user agent sent to the provider (API and video).
    static let userAgentKey = "userAgent"
    /// The provider drops requests from user agents it doesn't recognise; it answers this one.
    static let defaultUserAgent = "VLC/3.0.20 LibVLC/3.0.20"

    static var userAgent: String {
        let stored = UserDefaults.standard.string(forKey: userAgentKey) ?? ""
        return stored.isEmpty ? defaultUserAgent : stored
    }
}

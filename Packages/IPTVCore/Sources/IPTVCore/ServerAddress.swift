import Foundation

public enum ServerAddress {
    /// Turns what the user typed into `scheme://host[:port]`: adds `http://` when there is no
    /// scheme and drops any path, query and trailing slash. Nil when it isn't a usable address.
    public static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard let parsed = URLComponents(string: text),
              let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parsed.host, !host.isEmpty
        else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = parsed.port
        return components.url
    }
}

import Foundation

/// Hides the login in log text. mpv logs the stream URL ("Failed to open …", and "Playing: …" at
/// verbose levels), and Xtream URLs carry the username and password.
public enum LogRedaction {
    /// Masks every non-empty string in `secrets` (raw, and encoded the ways a URL path or query
    /// encodes it, since a redirect may put them anywhere), then any `/live/<user>/<pass>/` path and
    /// `username=`/`password=` value that is left.
    public static func redact(_ text: String, hiding secrets: [String] = []) -> String {
        // Longest first, so a username inside the password can't break up the password's match.
        let forms = Set(secrets.filter { !$0.isEmpty }.flatMap { secret in
            [secret]
                + [CharacterSet.urlPathAllowed, XtreamClient.unreserved].compactMap { secret.addingPercentEncoding(withAllowedCharacters: $0) }
        })
        var text = text
        for form in forms.sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: form, with: "***")
        }
        text = text.replacing(#/\/live\/[^\/\s]+\/[^\/\s]+\//#, with: "/live/***/***/")
        return text.replacing(#/(username|password)=[^&\s]*/#) { "\($0.output.1)=***" }
    }
}

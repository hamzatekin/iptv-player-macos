import Foundation

/// Helpers for reading loose JSON: numbers that arrive as strings, null fields, mixed types.
enum Lenient {
    static func parse(_ data: Data) throws -> Any {
        guard !data.isEmpty else { throw XtreamError.emptyResponse }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw XtreamError.decoding(error.localizedDescription)
        }
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.stringValue
        default:
            return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.intValue
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespaces)
            if let i = Int(t) { return i }
            if let d = Double(t), d.isFinite, abs(d) < 1e15 { return Int(d) }
            return nil
        default:
            return nil
        }
    }

    /// Non-empty string, or nil for null / missing / blank.
    static func nonEmptyString(_ value: Any?) -> String? {
        guard let s = string(value)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    static func date(unixSeconds value: Any?) -> Date? {
        int(value).map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    static func url(_ value: Any?) -> URL? {
        guard let s = nonEmptyString(value), let url = URL(string: s),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host() != nil
        else { return nil }
        return url
    }
}

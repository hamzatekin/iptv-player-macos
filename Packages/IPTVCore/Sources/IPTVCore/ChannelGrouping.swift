import Foundation

/// Turns the flat stream list into channels: "TRT 1 HD" and "TRT 1 FHD" in the same category
/// become one "TRT 1" channel with two variants.
public enum ChannelGrouping {
    /// Decorative rows the provider uses as headings, e.g. "∞∞∞ TURK ULUSAL ∞∞∞", "### TURK YEREL ###".
    public static func isSeparator(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasSuffix("|") { return true }
        var symbols = 0
        for ch in trimmed {
            if ch.isLetter || ch.isNumber || ch.isWhitespace { break }
            symbols += 1
        }
        return symbols >= 2
    }

    /// Splits a stream name into base name, quality and label. See `QualityParsing` rules in the tests.
    static func parse(_ name: String) -> (base: String, quality: Quality, label: String) {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        let whole = words.joined(separator: " ")
        for (index, word) in words.enumerated() {
            guard let quality = qualityToken(word) else { continue }
            if index == 0 { break }
            return (words[..<index].joined(separator: " "), quality, words[index...].joined(separator: " "))
        }
        return (whole, .unknown, "")
    }

    private static func qualityToken(_ word: String) -> Quality? {
        var token = word.uppercased()
        if token.hasSuffix("+") { token.removeLast() }
        switch token {
        case "FHD": return .fhd
        case "HD": return .hd
        case "SD": return .sd
        case "UHD", "4K": return .uhd
        case "HEVC", "H265": return .hevc
        case "RAW": return .raw
        default: return nil
        }
    }

    /// Groups within each category, drops separators, orders channels by `number`.
    public static func group(_ streams: [LiveStream]) -> [Channel] {
        struct Entry {
            let stream: LiveStream
            let base: String
            let quality: Quality
            let label: String
        }

        var order: [String] = []
        var buckets: [String: [Entry]] = [:]
        for stream in streams.sorted(by: { ($0.number, $0.id) < ($1.number, $1.id) }) where !isSeparator(stream.name) {
            let parsed = parse(stream.name)
            let id = "\(stream.categoryID ?? "none")/\(parsed.base.lowercased())"
            if buckets[id] == nil { order.append(id) }
            buckets[id, default: []].append(Entry(stream: stream, base: parsed.base, quality: parsed.quality, label: parsed.label))
        }

        let channels = order.map { id -> Channel in
            let entries = buckets[id]!  // entries are already in num order
            let variants = entries
                .sorted {
                    if $0.quality != $1.quality { return $0.quality < $1.quality }
                    if $0.label.count != $1.label.count { return $0.label.count < $1.label.count }
                    return ($0.stream.number, $0.stream.id) < ($1.stream.number, $1.stream.id)
                }
                .map { ChannelVariant(stream: $0.stream, quality: $0.quality, label: $0.label) }
            return Channel(
                id: id,
                name: entries[0].base,
                categoryID: entries[0].stream.categoryID,
                number: entries[0].stream.number,
                iconURL: variants[0].stream.iconURL ?? variants.lazy.compactMap(\.stream.iconURL).first,
                variants: variants
            )
        }
        return channels.sorted { ($0.number, $0.name) < ($1.number, $1.name) }
    }
}

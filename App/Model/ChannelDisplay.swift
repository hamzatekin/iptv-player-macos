import IPTVCore

extension Quality {
    /// Short text for a badge. Nil when the name had no quality token.
    var badge: String? {
        switch self {
        case .fhd: "FHD"
        case .hd: "HD"
        case .sd: "SD"
        case .raw: "RAW"
        case .hevc: "HEVC"
        case .uhd: "4K"
        case .unknown: nil
        }
    }
}

extension ChannelVariant {
    /// What menus call this variant, e.g. "FHD" or "HD TICARI | Mac Saati".
    var title: String { label.isEmpty ? "Standard" : label }
}

extension Channel {
    /// Each quality once, in variant order.
    var qualityBadges: [String] {
        var seen = Set<String>()
        return variants.compactMap { $0.quality.badge }.filter { seen.insert($0).inserted }
    }
}

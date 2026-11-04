import Foundation

/// An audio, video or subtitle track of the playing stream, from mpv's `track-list`.
public struct MediaTrack: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case video, audio, subtitle
    }

    /// mpv's id, counted per kind: the value `vid`, `aid` and `sid` take.
    public let trackID: Int
    public let kind: Kind
    /// The stream's own name for the track, e.g. an HLS rendition's NAME. DVB streams rarely have one.
    public let title: String?
    /// ISO 639 code as the stream gives it, e.g. "tur" or "en".
    public let language: String?
    public let codec: String?
    public let channelCount: Int?
    public let sampleRate: Int?
    public let isForced: Bool
    public let isSelected: Bool

    public var id: String { "\(kind.rawValue)/\(trackID)" }

    public init(
        trackID: Int, kind: Kind, title: String? = nil, language: String? = nil, codec: String? = nil,
        channelCount: Int? = nil, sampleRate: Int? = nil, isForced: Bool = false, isSelected: Bool = false
    ) {
        self.trackID = trackID
        self.kind = kind
        self.title = title
        self.language = language
        self.codec = codec
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.isForced = isForced
        self.isSelected = isSelected
    }

    /// mpv's `track-list` as Swift values (integers as `Int64`, flags as `Bool`). Entries that aren't
    /// video, audio or subtitles, or have no id, are left out.
    public static func parse(mpvTrackList list: [[String: Any]]) -> [MediaTrack] {
        list.compactMap { entry in
            let kind: Kind
            switch entry["type"] as? String {
            case "video": kind = .video
            case "audio": kind = .audio
            case "sub": kind = .subtitle
            default: return nil
            }
            guard let id = int(entry["id"]) else { return nil }
            return MediaTrack(
                trackID: id,
                kind: kind,
                title: text(entry["title"]),
                language: text(entry["lang"]),
                codec: text(entry["codec"]),
                channelCount: int(entry["demux-channel-count"]),
                sampleRate: int(entry["demux-samplerate"]),
                isForced: entry["forced"] as? Bool ?? false,
                isSelected: entry["selected"] as? Bool ?? false
            )
        }
    }

    /// What the track menus show: the language (or the stream's name for the track), and for audio
    /// the format too, since a channel often carries one language twice (stereo and 5.1).
    public func displayName(locale: Locale = .current) -> String {
        let languageName = language.flatMap { Self.languageName($0, locale: locale) }
        var name = languageName ?? title ?? "Track \(trackID)"
        if let title, let languageName, title.caseInsensitiveCompare(languageName) != .orderedSame {
            name += " (\(title))"
        }
        switch kind {
        case .audio:
            let format = [codec.map(CodecNames.name), channelCount.map(CodecNames.channels)].compactMap { $0 }
            if !format.isEmpty { name += " · " + format.joined(separator: " ") }
        case .subtitle:
            if isForced { name += " · forced" }
        case .video:
            break
        }
        return name
    }

    /// DVB marks tracks with codes that aren't languages: "qaa" is the original soundtrack, "qad"
    /// audio description. "und" is unknown.
    static func languageName(_ code: String, locale: Locale) -> String? {
        switch code.lowercased() {
        case "", "und", "zxx", "mis": return nil
        case "qaa": return "Original"
        case "qad": return "Audio Description"
        default: return locale.localizedString(forLanguageCode: code)
        }
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let value as Int64: Int(value)
        case let value as Int: value
        default: nil
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }
}

/// Technical details of the playing stream, for the stream info panel. Every field is optional:
/// mpv only knows some of them once video and audio are decoding.
public struct StreamInfo: Equatable, Sendable {
    public var width: Int?
    public var height: Int?
    public var fps: Double?
    public var videoCodec: String?
    /// mpv's `hwdec-current`: the hardware decoder in use, or "no".
    public var hardwareDecoder: String?
    /// Bits per second.
    public var videoBitrate: Double?
    public var audioCodec: String?
    public var audioChannels: Int?
    public var sampleRate: Int?
    /// Bits per second.
    public var audioBitrate: Double?
    public var droppedFrames: Int?
    /// Seconds of stream downloaded ahead of what is showing.
    public var bufferedSeconds: Double?

    public init() {}

    public struct Row: Hashable, Sendable {
        public let label: String
        public let value: String
    }

    public var rows: [Row] {
        var rows: [Row] = []
        if let width, let height, width > 0, height > 0 {
            var value = "\(width)×\(height)"
            if let fps, fps > 0 { value += " · \(Self.trim(fps, digits: 2)) fps" }
            rows.append(Row(label: "Picture", value: value))
        }
        if let videoCodec {
            var parts = [CodecNames.name(videoCodec)]
            if let hardwareDecoder {
                parts.append(hardwareDecoder == "no" || hardwareDecoder.isEmpty ? "software" : "hardware")
            }
            if let videoBitrate, videoBitrate > 0 { parts.append(Self.bitrate(videoBitrate)) }
            rows.append(Row(label: "Video", value: parts.joined(separator: " · ")))
        }
        if let audioCodec {
            var parts = [[CodecNames.name(audioCodec), audioChannels.map(CodecNames.channels)]
                .compactMap { $0 }.joined(separator: " ")]
            if let sampleRate, sampleRate > 0 { parts.append("\(Self.trim(Double(sampleRate) / 1000, digits: 1)) kHz") }
            if let audioBitrate, audioBitrate > 0 { parts.append(Self.bitrate(audioBitrate)) }
            rows.append(Row(label: "Audio", value: parts.joined(separator: " · ")))
        }
        if let droppedFrames { rows.append(Row(label: "Dropped frames", value: "\(droppedFrames)")) }
        if let bufferedSeconds { rows.append(Row(label: "Buffered", value: "\(Self.trim(bufferedSeconds, digits: 1)) s")) }
        return rows
    }

    static func bitrate(_ bitsPerSecond: Double) -> String {
        bitsPerSecond >= 1_000_000
            ? "\(trim(bitsPerSecond / 1_000_000, digits: 1)) Mb/s"
            : "\(Int((bitsPerSecond / 1000).rounded())) kb/s"
    }

    /// At most `digits` decimals, without trailing zeros: 25 → "25", 29.97 → "29.97", 44.1 → "44.1".
    static func trim(_ value: Double, digits: Int) -> String {
        var text = String(format: "%.\(digits)f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

/// mpv's codec names ("h264", "eac3") as people know them.
enum CodecNames {
    static func name(_ codec: String) -> String {
        switch codec.lowercased() {
        case "h264": "H.264"
        case "hevc", "h265": "HEVC"
        case "mpeg2video": "MPEG-2"
        case "av1": "AV1"
        case "vp9": "VP9"
        case "aac": "AAC"
        case "ac3": "AC-3"
        case "eac3": "E-AC-3"
        case "mp2": "MP2"
        case "mp3": "MP3"
        case "opus": "Opus"
        case "flac": "FLAC"
        default: codec.uppercased()
        }
    }

    static func channels(_ count: Int) -> String {
        switch count {
        case 1: "mono"
        case 2: "stereo"
        case 6: "5.1"
        case 8: "7.1"
        default: "\(count) channels"
        }
    }
}

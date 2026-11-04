import Foundation
import Testing
@testable import IPTVCore

@Suite struct MediaTrackTests {
    private let english = Locale(identifier: "en_GB")

    @Test func parsesMPVTrackList() {
        let list: [[String: Any]] = [
            ["id": Int64(1), "type": "video", "codec": "h264", "selected": true],
            ["id": Int64(1), "type": "audio", "lang": "tur", "codec": "aac", "demux-channel-count": Int64(2),
             "demux-samplerate": Int64(48000), "selected": true],
            ["id": Int64(2), "type": "audio", "lang": "eng", "codec": "ac3", "demux-channel-count": Int64(6)],
            ["id": Int64(1), "type": "sub", "lang": "tur", "title": "", "forced": true],
            ["id": Int64(9), "type": "something-new"],
            ["type": "audio"],
        ]
        let tracks = MediaTrack.parse(mpvTrackList: list)
        #expect(tracks.map(\.id) == ["video/1", "audio/1", "audio/2", "subtitle/1"])
        #expect(tracks[1] == MediaTrack(
            trackID: 1, kind: .audio, language: "tur", codec: "aac", channelCount: 2, sampleRate: 48000, isSelected: true
        ))
        #expect(tracks[3].title == nil)
        #expect(tracks[3].isForced)
        #expect(!tracks[2].isSelected)
    }

    @Test(arguments: [
        (MediaTrack(trackID: 1, kind: .audio, language: "tur", codec: "aac", channelCount: 2), "Turkish · AAC stereo"),
        (MediaTrack(trackID: 2, kind: .audio, language: "eng", codec: "eac3", channelCount: 6), "English · E-AC-3 5.1"),
        (MediaTrack(trackID: 3, kind: .audio, language: "qaa", codec: "mp2"), "Original · MP2"),
        (MediaTrack(trackID: 4, kind: .audio), "Track 4"),
        (MediaTrack(trackID: 5, kind: .audio, title: "Commentary", language: "und"), "Commentary"),
        (MediaTrack(trackID: 1, kind: .audio, title: "English", language: "en"), "English"),
        (MediaTrack(trackID: 1, kind: .audio, title: "BipBop Audio 2", language: "en"), "English (BipBop Audio 2)"),
        (MediaTrack(trackID: 1, kind: .subtitle, language: "fre", codec: "webvtt", isForced: true), "French · forced"),
        (MediaTrack(trackID: 2, kind: .subtitle, language: "tr", codec: "dvb_subtitle"), "Turkish"),
    ])
    func displayNames(track: MediaTrack, expected: String) {
        #expect(track.displayName(locale: english) == expected)
    }

    @Test func streamInfoRows() {
        var info = StreamInfo()
        info.width = 1920
        info.height = 1080
        info.fps = 25
        info.videoCodec = "h264"
        info.hardwareDecoder = "videotoolbox"
        info.videoBitrate = 4_230_000
        info.audioCodec = "aac"
        info.audioChannels = 2
        info.sampleRate = 44100
        info.audioBitrate = 127_600
        info.droppedFrames = 0
        info.bufferedSeconds = 3.24
        #expect(info.rows.map { "\($0.label): \($0.value)" } == [
            "Picture: 1920×1080 · 25 fps",
            "Video: H.264 · hardware · 4.2 Mb/s",
            "Audio: AAC stereo · 44.1 kHz · 128 kb/s",
            "Dropped frames: 0",
            "Buffered: 3.2 s",
        ])
    }

    @Test func streamInfoLeavesOutWhatMPVDoesNotKnowYet() {
        var info = StreamInfo()
        #expect(info.rows.isEmpty)
        info.videoCodec = "hevc"
        info.hardwareDecoder = "no"
        info.fps = 29.97
        #expect(info.rows == [StreamInfo.Row(label: "Video", value: "HEVC · software")])
    }

    @Test func trimmedNumbers() {
        #expect(StreamInfo.trim(29.97, digits: 2) == "29.97")
        #expect(StreamInfo.trim(50.0, digits: 2) == "50")
        #expect(StreamInfo.trim(48, digits: 1) == "48")
        #expect(StreamInfo.bitrate(820_000) == "820 kb/s")
    }
}

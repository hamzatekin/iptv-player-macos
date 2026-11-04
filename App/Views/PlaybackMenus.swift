import IPTVCore
import SwiftUI

/// Menu contents shared by the Playback menu and the player's own buttons.

/// The stream's audio tracks, the selected one ticked.
struct AudioTrackItems: View {
    let player: MPVPlayer

    var body: some View {
        ForEach(player.tracks.filter { $0.kind == .audio }) { track in
            Toggle(track.displayName(), isOn: Binding(
                get: { track.isSelected },
                set: { if $0 { player.selectAudio(track.trackID) } }
            ))
        }
    }
}

/// Off, then the stream's subtitle tracks.
struct SubtitleItems: View {
    let player: MPVPlayer

    var body: some View {
        let subtitles = player.tracks.filter { $0.kind == .subtitle }
        Toggle("Off", isOn: Binding(
            get: { !subtitles.contains(where: \.isSelected) },
            set: { if $0 { player.selectSubtitle(nil) } }
        ))
        ForEach(subtitles) { track in
            Toggle(track.displayName(), isOn: Binding(
                get: { track.isSelected },
                set: { if $0 { player.selectSubtitle(track.trackID) } }
            ))
        }
    }
}

extension MPVPlayer {
    /// Worth a menu: a choice of audio, or any subtitles.
    var hasTrackChoice: Bool {
        tracks.count { $0.kind == .audio } > 1 || tracks.contains { $0.kind == .subtitle }
    }
}

/// Stop after a while, or when the programme ends.
struct SleepTimerItems: View {
    let model: AppModel

    private static let choices: [(minutes: Int, title: String)] = [
        (15, "15 Minutes"), (30, "30 Minutes"), (45, "45 Minutes"),
        (60, "1 Hour"), (90, "1 Hour 30 Minutes"), (120, "2 Hours"),
    ]

    var body: some View {
        if let sleepAt = model.sleepAt {
            Text("Stops at \(sleepAt.formatted(date: .omitted, time: .shortened))")
            Button("Turn Off") { model.setSleepTimer(nil) }
            Divider()
        }
        ForEach(Self.choices, id: \.minutes) { choice in
            Button(choice.title) { model.setSleepTimer(choice.minutes) }
        }
        if let end = model.currentProgrammeEnd {
            Divider()
            Button("End of Programme (\(end.formatted(date: .omitted, time: .shortened)))") {
                model.sleepAtEndOfProgramme()
            }
        }
    }
}

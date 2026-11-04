import SwiftUI

struct PlaybackCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Playback") {
            Button("Channel Up") { model.step(-1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Channel Down") { model.step(1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button(model.previousChannel.map { "Previous Channel: \($0.name)" } ?? "Previous Channel") {
                model.playPrevious()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(model.previousChannel == nil)
            Divider()
            Button("Play/Pause") { model.togglePlayPause() }
                .keyboardShortcut("p", modifiers: .command)
            Button("Stop") { model.stop() }
                .keyboardShortcut(".", modifiers: .command)
            Divider()
            Button(model.player.isMuted ? "Unmute" : "Mute") { model.player.toggleMute() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Volume Up") { model.changeVolume(by: 10) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Volume Down") { model.changeVolume(by: -10) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Menu("Audio") { AudioTrackItems(player: model.player) }
                .disabled(!model.player.tracks.contains { $0.kind == .audio })
            Menu("Subtitles") { SubtitleItems(player: model.player) }
                .disabled(!model.player.tracks.contains { $0.kind == .subtitle })
            Divider()
            Button(model.window.isMini ? "Exit Mini Player" : "Mini Player") { model.window.toggleMini() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button(model.showsStreamInfo ? "Hide Stream Info" : "Show Stream Info") { model.showsStreamInfo.toggle() }
                .keyboardShortcut("i", modifiers: .command)
            Menu("Sleep Timer") { SleepTimerItems(model: model) }
            Divider()
            Button("Toggle Favorite") { model.toggleFavoriteOfCurrent() }
                .keyboardShortcut("d", modifiers: .command)
            Button("Refresh Channels") { Task { await model.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
        }
    }
}

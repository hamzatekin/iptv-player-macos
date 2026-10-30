import SwiftUI

struct PlaybackCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Playback") {
            Button("Channel Up") { model.step(-1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Channel Down") { model.step(1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            Button("Play/Pause") { model.player.togglePause() }
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
            Divider()
            Button(model.window.isMini ? "Exit Mini Player" : "Mini Player") { model.window.toggleMini() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Toggle Favorite") { model.toggleFavoriteOfCurrent() }
                .keyboardShortcut("d", modifiers: .command)
            Button("Refresh Channels") { Task { await model.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
        }
    }
}

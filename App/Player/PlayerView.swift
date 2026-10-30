import SwiftUI

/// Shows the player's persistent video view. SwiftUI may rebuild this wrapper; the NSView inside
/// stays the same, so mpv keeps drawing.
struct PlayerView: NSViewRepresentable {
    let player: MPVPlayer

    func makeNSView(context: Context) -> NSView { player.videoView }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

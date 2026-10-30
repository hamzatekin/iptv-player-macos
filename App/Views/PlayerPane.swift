import AppKit
import SwiftUI

struct PlayerPane: View {
    @Environment(AppModel.self) private var model
    @State private var isHovering = false
    @State private var isMoving = false
    @State private var hideTask: Task<Void, Never>?

    private var controlsVisible: Bool {
        isHovering && (isMoving || model.player.state != .playing)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerView(player: model.player)
            // Clicks on mpv's AppKit view never reach SwiftUI gestures, so this layer takes them.
            // Not on the whole pane: a double-click on a control's button would toggle full screen too.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.window.toggleFullScreen() }
            // mpv leaves the last frame on its layer when a stream stops or fails, which looked like the
            // old channel was still on under the new one's spinner or error.
            Color.black
                .opacity(model.player.state == .playing ? 0 : 1)
                .allowsHitTesting(false)
            PlayerStatusOverlay()
            PlayerControls()
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .animation(.easeOut(duration: 0.2), value: controlsVisible)
        }
        .frame(minWidth: 320, minHeight: 180)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
                isMoving = true
                scheduleHide()
            case .ended:
                hideTask?.cancel()
                isHovering = false
                isMoving = false
            }
        }
    }

    /// Controls stay up while the mouse moves and go away 3 seconds after it stops.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            isMoving = false
            if model.player.state == .playing { NSCursor.setHiddenUntilMouseMoves(true) }
        }
    }
}

/// Idle, loading and failed states drawn over the video.
private struct PlayerStatusOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        Group {
            switch player.state {
            case .idle:
                if model.playingChannel == nil {
                    message("Choose a channel", systemImage: "tv")
                } else {
                    VStack(spacing: 12) {
                        message("Stopped", systemImage: "stop.circle")
                        Button("Play") { model.retry() }
                    }
                }
            case .loading:
                ProgressView().controlSize(.large)
            case .playing:
                if player.isBuffering { ProgressView().controlSize(.large) }
            case .failed(let reason):
                if model.isDiagnosing {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Checking what went wrong…").font(.callout).foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    let problem = model.playbackProblem
                    VStack(spacing: 12) {
                        message(
                            problem?.title ?? "Couldn't play this channel",
                            systemImage: problem?.systemImage ?? "exclamationmark.triangle",
                            detail: problem?.detail ?? reason
                        )
                        Button("Retry") { model.retry() }
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    private func message(_ title: String, systemImage: String, detail: String? = nil) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 36))
            Text(title).font(.title3)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}

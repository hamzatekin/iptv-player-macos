import MediaPlayer

/// Media keys and Control Center. Publishing what plays makes macOS send the keyboard's play/pause,
/// previous and next keys here; Control Center shows the channel and its programme. mpv's own media
/// key handling stays off (`input-media-keys`).
@MainActor
final class NowPlaying {
    private unowned let model: AppModel
    private var published: Snapshot?

    /// What Control Center shows, compared so the system is only told about real changes.
    private struct Snapshot: Equatable {
        var title: String
        var programme: String?
        var state: MPNowPlayingPlaybackState
    }

    init(model: AppModel) {
        self.model = model
        let center = MPRemoteCommandCenter.shared()
        handle(center.togglePlayPauseCommand) { $0.togglePlayPause() }
        handle(center.playCommand) { model in
            if model.player.isPaused { model.player.togglePause() } else if model.player.state != .playing { model.retry() }
        }
        handle(center.pauseCommand) { model in
            if !model.player.isPaused { model.player.togglePause() }
        }
        handle(center.stopCommand) { $0.stop() }
        // Track keys change channel, like Channel Up and Down in the Playback menu.
        handle(center.nextTrackCommand) { $0.step(1) }
        handle(center.previousTrackCommand) { $0.step(-1) }
        track()
    }

    private func handle(_ command: MPRemoteCommand, _ action: @escaping @MainActor (AppModel) -> Void) {
        command.isEnabled = true
        command.addTarget { [weak self] _ in
            // The handler may run off the main thread; the model lives on it.
            Task { @MainActor in
                guard let self else { return }
                action(self.model)
            }
            return .success
        }
    }

    /// Publishes now, and again whenever something it read changes.
    private func track() {
        withObservationTracking {
            publish()
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
    }

    private func publish() {
        let player = model.player
        let snapshot: Snapshot?
        switch player.state {
        case .idle, .failed:
            snapshot = nil
        case .loading, .playing:
            let channel = model.playingChannel
            snapshot = Snapshot(
                title: channel?.name ?? "IPTV Player",
                programme: channel.flatMap { model.nowNext(for: $0)?.now?.title },
                state: player.isPaused ? .paused : .playing
            )
        }
        guard snapshot != published else { return }
        published = snapshot
        let info = MPNowPlayingInfoCenter.default()
        guard let snapshot else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        var values: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.state == .paused ? 0.0 : 1.0,
        ]
        if let programme = snapshot.programme { values[MPMediaItemPropertyArtist] = programme }
        info.nowPlayingInfo = values
        info.playbackState = snapshot.state
    }
}

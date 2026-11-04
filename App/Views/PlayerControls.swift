import IPTVCore
import SwiftUI

/// Top bar (channel name, audio and subtitles, quality) and bottom bar (now/next, volume, previous
/// channel, sleep timer, stream info, mini, full screen).
struct PlayerControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let compact = model.window.isMini
        VStack(spacing: 0) {
            if let channel = model.playingChannel {
                topBar(channel)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                if !compact, let channel = model.playingChannel {
                    NowNextView(channel: channel)
                }
                buttonBar
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fade(from: .bottom))
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    /// A bar's backdrop. It covers the video, so it takes the video's double-click (full screen) too.
    private func fade(from edge: Edge) -> some View {
        LinearGradient(
            colors: [.black.opacity(0.75), .clear],
            startPoint: edge == .bottom ? .bottom : .top,
            endPoint: edge == .bottom ? .top : .bottom
        )
        .onTapGesture(count: 2) { model.window.toggleFullScreen() }
    }

    private func topBar(_ channel: Channel) -> some View {
        HStack {
            Text(channel.name)
                .font(.title3.bold())
                .lineLimit(1)
            Spacer()
            if model.player.hasTrackChoice {
                Menu {
                    Section("Audio") { AudioTrackItems(player: model.player) }
                    Section("Subtitles") { SubtitleItems(player: model.player) }
                } label: {
                    Image(systemName: "captions.bubble")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Audio and Subtitles")
            }
            if channel.variants.count > 1 {
                Menu {
                    ForEach(channel.variants) { variant in
                        Button {
                            model.play(channel, variant: variant)
                        } label: {
                            if variant.stream.id == model.playingStreamID {
                                Label(variant.title, systemImage: "checkmark")
                            } else {
                                Text(variant.title)
                            }
                        }
                    }
                } label: {
                    Label(currentVariantTitle(channel), systemImage: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Quality")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(fade(from: .top))
    }

    private func currentVariantTitle(_ channel: Channel) -> String {
        channel.variants.first { $0.stream.id == model.playingStreamID }?.title ?? "Quality"
    }

    private var buttonBar: some View {
        let player = model.player
        return HStack(spacing: 14) {
            Button { player.toggleMute() } label: {
                Image(systemName: player.isMuted || player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 20)
            }
            .help(player.isMuted ? "Unmute" : "Mute")
            Slider(
                value: Binding(get: { player.volume }, set: { player.setVolume($0) }),
                in: 0...100
            )
            .frame(width: 120)
            .controlSize(.small)
            .accessibilityLabel("Volume")
            Spacer()
            if let previous = model.previousChannel {
                Button { model.playPrevious() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help("Back to \(previous.name) (⌘L)")
            }
            Menu {
                SleepTimerItems(model: model)
            } label: {
                Image(systemName: model.sleepAt == nil ? "moon" : "moon.zzz.fill")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(model.sleepAt.map { "Sleep timer: stops at \($0.formatted(date: .omitted, time: .shortened))" } ?? "Sleep Timer")
            Button { model.showsStreamInfo.toggle() } label: {
                Image(systemName: model.showsStreamInfo ? "info.circle.fill" : "info.circle")
            }
            .help(model.showsStreamInfo ? "Hide Stream Info (⌘I)" : "Show Stream Info (⌘I)")
            Button { model.window.toggleMini() } label: {
                Image(systemName: model.window.isMini ? "arrow.up.left.and.arrow.down.right" : "pip.enter")
            }
            .help(model.window.isMini ? "Exit Mini Player" : "Mini Player")
            if !model.window.isMini {
                Button { model.window.toggleFullScreen() } label: {
                    Image(systemName: model.window.isFullScreen
                        ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .help(model.window.isFullScreen ? "Exit Full Screen" : "Full Screen")
            }
        }
        .buttonStyle(.plain)
        .font(.title3)
    }
}

private struct NowNextView: View {
    @Environment(AppModel.self) private var model
    let channel: Channel

    var body: some View {
        // Re-evaluated every 15 seconds so the programme and its progress bar follow the clock.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let nowNext = model.nowNext(for: channel, at: context.date) {
                VStack(alignment: .leading, spacing: 4) {
                    if let now = nowNext.now {
                        HStack {
                            Text(now.title).font(.headline).lineLimit(1)
                            Text(timeRange(now)).foregroundStyle(.white.opacity(0.7))
                        }
                        if let progress = nowNext.progress(at: context.date) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .frame(maxWidth: 360)
                        }
                    }
                    if let next = nowNext.next {
                        HStack(spacing: 6) {
                            Text("Next").foregroundStyle(.white.opacity(0.7))
                            Text(next.title).lineLimit(1)
                            Text(timeRange(next)).foregroundStyle(.white.opacity(0.7))
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private func timeRange(_ entry: EPGEntry) -> String {
        let start = entry.start.formatted(date: .omitted, time: .shortened)
        let end = entry.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

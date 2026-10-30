import IPTVCore
import SwiftUI

struct ChannelRow: View {
    @Environment(AppModel.self) private var model
    let channel: Channel

    var body: some View {
        HStack(spacing: 10) {
            ChannelLogo(channel: channel)
            // Badges sit on the second line so the name gets the full width: on the first line they
            // squeezed "beIN SPORTS 1/3/4" down to an identical "beIN…".
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(channel.qualityBadges, id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    // Always there, blank until the guide loads, so rows keep their height when it arrives.
                    Text(model.nowNext(for: channel)?.now?.title ?? " ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Playing")
            }
            Button {
                model.toggleFavorite(channel)
            } label: {
                Image(systemName: model.isFavorite(channel) ? "star.fill" : "star")
                    .foregroundStyle(model.isFavorite(channel) ? Color.yellow : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(model.isFavorite(channel) ? "Remove from Favorites" : "Add to Favorites")
        }
        .padding(.vertical, 2)
        .onAppear { model.requestNowNext(for: channel) }
    }

    private var isPlaying: Bool {
        guard model.playingChannelID == channel.id else { return false }
        switch model.player.state {
        case .loading, .playing: return true
        case .idle, .failed: return false
        }
    }
}

private struct ChannelLogo: View {
    let channel: Channel

    var body: some View {
        AsyncImage(url: channel.iconURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                placeholder
            }
        }
        .frame(width: 28, height: 28)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary)
            .overlay {
                Text(channel.name.prefix(1).uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
    }
}

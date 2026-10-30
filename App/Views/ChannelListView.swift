import IPTVCore
import SwiftUI

struct ChannelListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let channels = model.visibleChannels
        List(channels, selection: $model.selectedChannelID) { channel in
            ChannelRow(channel: channel)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let channel = model.channel(id: ids.first) {
                contextMenu(for: channel)
            }
        } primaryAction: { ids in
            if let channel = model.channel(id: ids.first) { model.play(channel) }
        }
        .searchable(text: $model.searchText, prompt: "Search all channels")
        .overlay {
            if channels.isEmpty { emptyState }
        }
        .navigationTitle(model.listTitle)
        .navigationSubtitle("\(channels.count) channels")
    }

    @ViewBuilder
    private func contextMenu(for channel: Channel) -> some View {
        Button("Play") { model.play(channel) }
        if channel.variants.count > 1 {
            Menu("Quality") {
                ForEach(channel.variants) { variant in
                    Button(variant.title) { model.play(channel, variant: variant) }
                }
            }
        }
        Divider()
        Button(model.isFavorite(channel) ? "Remove from Favorites" : "Add to Favorites") {
            model.toggleFavorite(channel)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else if model.selection == .favorites {
            ContentUnavailableView(
                "No Favorites", systemImage: "star",
                description: Text("Click the star next to a channel to add it here.")
            )
        } else {
            ContentUnavailableView("No Channels", systemImage: "tv")
        }
    }
}

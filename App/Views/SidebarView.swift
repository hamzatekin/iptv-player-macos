import IPTVCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: selection) {
            Label("Favorites", systemImage: "star")
                .badge(model.favoritesCount)
                .tag(SidebarSelection.favorites)
            Label("All Channels", systemImage: "tv")
                .badge(model.channels.count)
                .tag(SidebarSelection.all)

            Section("Categories") {
                ForEach(model.categoryRows) { row in
                    Text(row.category.name)
                        .badge(row.count)
                        .tag(SidebarSelection.category(row.id))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    private var selection: Binding<SidebarSelection?> {
        Binding(get: { model.selection }, set: { if let value = $0 { model.select(value) } })
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let notice = model.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let fetchedAt = model.catalog?.fetchedAt {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text("Updated \(fetchedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh channels")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

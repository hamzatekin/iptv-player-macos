import SwiftUI

/// Sidebar | channel list | player.
///
/// The player is an overlay, not the split view's detail column: macOS's NavigationSplitView ignores
/// `.detailOnly`, so the columns stayed visible in mini mode and held the window wide. The detail
/// column only reports where the player goes. In full screen and mini mode the split view is removed
/// and the player fills the window. The player stays at the same place in the view tree throughout,
/// so mpv's view is never moved.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var showsAccount = false

    var body: some View {
        ZStack {
            if !model.window.showsPlayerOnly {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
                } content: {
                    ChannelListView()
                        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
                } detail: {
                    // Carries the player's minimum size, which the overlay can't give the window.
                    Color.clear
                        .frame(minWidth: 320, minHeight: 180)
                        .anchorPreference(key: PlayerFrameKey.self, value: .bounds) { $0 }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showsAccount = true
                        } label: {
                            Label("Account", systemImage: "person.crop.circle")
                        }
                        .help("Account and login")
                    }
                }
            }
        }
        .sheet(isPresented: $showsAccount) {
            AccountSheet().environment(model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlayPreferenceValue(PlayerFrameKey.self) { anchor in
            GeometryReader { proxy in
                let frame = model.window.showsPlayerOnly ? nil : anchor.map { proxy[$0] }
                PlayerPane()
                    .frame(width: frame?.width ?? proxy.size.width, height: frame?.height ?? proxy.size.height)
                    .offset(x: frame?.minX ?? 0, y: frame?.minY ?? 0)
            }
            // Player only: the video also goes under the title bar, or mini mode lost 32 pt of 270 to it.
            .ignoresSafeArea(edges: model.window.showsPlayerOnly ? .all : [])
        }
        .toolbar(model.window.isMini ? .hidden : .automatic, for: .windowToolbar)
    }
}

/// Where the split view's detail column is, so the player overlay can sit on top of it.
private struct PlayerFrameKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

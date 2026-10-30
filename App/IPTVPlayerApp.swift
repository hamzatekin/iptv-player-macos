import AppKit
import IPTVCore
import SwiftUI

@main
struct IPTVPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    init() {
        #if DEBUG
        // Flush logs line by line even when stdout is a file (make run, log capture).
        setvbuf(stdout, nil, _IOLBF, 0)
        #endif
    }

    var body: some Scene {
        Window("IPTV Player", id: AppDelegate.mainWindowID) {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 1180, height: 720)
        .windowResizability(.contentMinSize)
        .commands { PlaybackCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Clicking the Dock icon with no window open brings the main window back.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let mainWindowID = "main"
    /// Set by the root view, which has the `openWindow` action.
    @MainActor static var openMainWindow: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let minimized = sender.windows.first(where: \.isMiniaturized) {
            minimized.deminiaturize(nil)
            return false
        }
        guard let open = MainActor.assumeIsolated({ Self.openMainWindow }) else { return true }
        open()
        return false
    }
}

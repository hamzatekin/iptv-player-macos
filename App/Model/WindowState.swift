import AppKit
import Observation

/// The main window's full screen and mini mode. Both show only the player column, so the player
/// view is never moved: the split view just hides the other columns.
@MainActor
@Observable
final class WindowState {
    private(set) var isFullScreen = false
    private(set) var isMini = false

    var showsPlayerOnly: Bool { isFullScreen || isMini }

    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var restore: (frame: NSRect, level: NSWindow.Level, behavior: NSWindow.CollectionBehavior)?

    private static let miniContentSize = NSSize(width: 480, height: 270)
    private static let miniMargin: CGFloat = 16

    func attach(_ window: NSWindow?) {
        guard window !== self.window else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        self.window = window
        isMini = false
        restore = nil
        guard let window else {
            isFullScreen = false
            return
        }
        isFullScreen = window.styleMask.contains(.fullScreen)
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isFullScreen = true }
            },
            center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isFullScreen = false }
            },
            // Leave mini mode before quitting, so the frame macOS saves for next launch is the
            // normal one rather than the 480×270 mini frame.
            center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setMini(false, animate: false) }
            },
        ]
    }

    func toggleFullScreen() {
        if isMini { setMini(false) }
        window?.toggleFullScreen(nil)
    }

    func toggleMini() { setMini(!isMini) }

    func setMini(_ on: Bool, animate: Bool = true) {
        guard let window, on != isMini else { return }
        if on {
            guard !isFullScreen else { return }
            restore = (window.frame, window.level, window.collectionBehavior)
            isMini = true
            window.level = .floating
            // Follow the user to other Spaces, including another app's full screen Space. Only one
            // of the full screen flags may be set, so drop the others while mini.
            window.collectionBehavior.subtract([.fullScreenPrimary, .fullScreenNone])
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            // The split view only lowers the window's minimum size on its next layout pass, so
            // lower it now and set the frame on the next run loop turn.
            window.contentMinSize = NSSize(width: 320, height: 180)
            window.contentAspectRatio = NSSize(width: 16, height: 9)
            let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.miniContentSize))
            frame.origin = NSPoint(x: screen.maxX - frame.width - Self.miniMargin, y: screen.minY + Self.miniMargin)
            DispatchQueue.main.async { window.setFrame(frame, display: true, animate: animate) }
        } else {
            isMini = false
            window.level = restore?.level ?? .normal
            if let behavior = restore?.behavior { window.collectionBehavior = behavior }
            // Resize increments and the aspect ratio override each other: this clears the ratio.
            window.resizeIncrements = NSSize(width: 1, height: 1)
            if let frame = restore?.frame { window.setFrame(frame, display: true, animate: animate) }
            restore = nil
        }
    }
}

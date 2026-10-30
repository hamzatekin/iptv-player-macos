import AppKit
import SwiftUI

/// Reports the NSWindow that hosts the view it is attached to.
struct WindowAccessor: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> AccessorView {
        let view = AccessorView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: AccessorView, context: Context) {
        nsView.onChange = onChange
    }

    final class AccessorView: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Not synchronously: this can run inside a SwiftUI update.
            DispatchQueue.main.async { [weak self] in self?.onChange?(self?.window) }
        }
    }
}

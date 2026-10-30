import AppKit

/// Metal layer mpv draws into (via MoltenVK). Based on MPVKit's macOS demo.
final class MetalLayer: CAMetalLayer {
    // MoltenVK sets drawableSize to 1x1 to force a presentation to finish, which flickers and can
    // leave the layer stuck at 1x1. https://github.com/mpv-player/mpv/pull/13651
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
}

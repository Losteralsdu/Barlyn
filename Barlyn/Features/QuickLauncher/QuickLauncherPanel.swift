import AppKit
import SwiftUI

/// The floating window the launcher lives in.
///
/// A borderless `NSPanel` rather than a SwiftUI `Window` scene, because a launcher has
/// requirements a standard window cannot express: it must float above other apps, must not appear
/// in the window list, must vanish when it loses focus, and must be positionable over the active
/// screen. `NSPanel` gives all of that; a `Window` scene gives none of it.
final class QuickLauncherPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 400),
            // `.nonactivatingPanel` keeps the panel from dragging the whole app forward as a
            // side effect of being shown.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        // Shows over full-screen apps and follows the user between Spaces, which is the whole
        // point of a global launcher.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    /// A borderless panel refuses key status by default, which would leave the search field
    /// unable to receive a single keystroke.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Centres horizontally and sits above centre vertically, where Spotlight puts itself —
    /// the eye lands there first and it leaves room for results to grow downward.
    func positionOnActiveScreen() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + visible.height * 0.12
            )
        )
    }
}

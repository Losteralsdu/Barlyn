import AppKit
import OSLog

/// AppKit lifecycle hooks that SwiftUI's `App` protocol does not expose.
///
/// Kept deliberately thin. It exists now because the things Barlyn will need shortly —
/// installing the menu bar item, deciding the activation policy, registering global hotkeys,
/// tearing down event taps on termination — are all AppKit-level concerns with no SwiftUI
/// equivalent. Those get wired here in later phases; none of them belong in a View.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.app.notice("Application did finish launching")
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.app.notice("Application will terminate")
    }

    /// Once the app becomes a menu bar agent (Phase 2) there will be no Dock icon, so this
    /// currently-default behaviour is stated explicitly to make the later change deliberate.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

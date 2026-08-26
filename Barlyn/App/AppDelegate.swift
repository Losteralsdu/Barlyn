import AppKit
import OSLog

/// AppKit lifecycle hooks that SwiftUI's `App` protocol does not expose.
///
/// Kept deliberately thin. Global hotkey registration (Phase 5/8) and event tap teardown will
/// land here; none of it belongs in a View.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.app.notice("Application did finish launching")
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.app.notice("Application will terminate")
    }

    /// Barlyn is a menu bar agent: closing the dashboard or Settings must not quit it. The app
    /// stays alive in the menu bar until the user explicitly chooses Quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

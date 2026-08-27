import AppKit
import OSLog
import SwiftUI

/// Executes a launcher result's action.
///
/// Single place where actions become side effects, so providers stay pure data sources and every
/// externally visible thing the launcher can do is auditable in one file.
@MainActor
struct LauncherActionRunner {
    let openWindow: (WindowID) -> Void
    let openSettings: () -> Void
    /// Routed through `ClipboardService` rather than touching `NSPasteboard` directly, so
    /// restoring a history entry is not immediately re-captured as a fresh copy.
    let copyToPasteboard: (String) -> Void

    /// Returns whether the launcher should close. Informational rows leave it open so the user
    /// can keep reading.
    @discardableResult
    func run(_ action: LauncherAction) -> Bool {
        switch action {
        case .none:
            return false

        case .openWindow(let id):
            // An accessory app is not frontmost when its panel is used, so a new window would
            // otherwise open behind whatever the user was working in.
            NSApp.activate()
            openWindow(id)
            return true

        case .openSettings:
            NSApp.activate()
            openSettings()
            return true

        case .launchApplication(let url):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    AppLog.launcher.error(
                        "Failed to launch \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            return true

        case .copyToPasteboard(let string):
            // Clipboard contents are user data and are never logged, at any level (§37).
            copyToPasteboard(string)
            return true

        case .quitApp:
            NSApplication.shared.terminate(nil)
            return true
        }
    }
}

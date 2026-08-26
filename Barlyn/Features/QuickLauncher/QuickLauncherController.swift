import AppKit
import OSLog
import SwiftUI

/// Owns the launcher's window, selection state and lifecycle.
///
/// Kept out of the view because the panel outlives any particular SwiftUI render and because
/// showing it is triggered by a global hotkey, which has no view context at all.
@MainActor
@Observable
final class QuickLauncherController {
    private let searchService: LauncherSearchService
    private let sampler: MetricSampler
    private let registry: MetricRegistry

    private(set) var queryText = ""
    private(set) var selectedIndex = 0
    private(set) var isVisible = false

    private var panel: QuickLauncherPanel?
    /// `nonisolated(unsafe)` so `deinit`, which is never actor-isolated, can unregister the
    /// observer. Every other access is on the main actor, and `deinit` only runs once no other
    /// reference survives, so there is no concurrent access to guard against.
    private nonisolated(unsafe) var resignObserver: (any NSObjectProtocol)?

    /// Set by the app once SwiftUI's window-opening actions are available.
    var actionRunner: LauncherActionRunner?

    var results: [LauncherResult] { searchService.results }

    init(searchService: LauncherSearchService, sampler: MetricSampler, registry: MetricRegistry) {
        self.searchService = searchService
        self.sampler = sampler
        self.registry = registry
    }

    // MARK: - Visibility

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        queryText = ""
        selectedIndex = 0
        searchService.search("")

        // Metrics shown in the launcher must be live while it is open, and must stop costing
        // anything the moment it closes.
        sampler.setDemand(Set(registry.descriptors.map(\.id)), for: .quickLauncher)

        panel.positionOnActiveScreen()
        // An accessory app has no Dock icon and is never frontmost, so without this the panel
        // appears but keystrokes keep going to whatever the user was using.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        searchService.clear()
        queryText = ""
        selectedIndex = 0
        sampler.clearDemand(for: .quickLauncher)
    }

    // MARK: - Search and selection

    func updateQuery(_ text: String) {
        queryText = text
        // Selection resets on every edit: keeping an index into a list that has just changed
        // would point at an unrelated row.
        selectedIndex = 0
        searchService.search(text)
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        // Wraps, so holding Down cycles rather than sticking at the bottom.
        let count = results.count
        selectedIndex = ((selectedIndex + offset) % count + count) % count
    }

    func runSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        run(results[selectedIndex])
    }

    func run(_ result: LauncherResult) {
        guard let actionRunner else {
            AppLog.launcher.error("No action runner configured; launcher action ignored")
            return
        }
        // Informational rows (live metrics) leave the launcher open so the user can keep reading.
        if actionRunner.run(result.action) {
            hide()
        }
    }

    // MARK: - Panel

    private func makePanel() -> QuickLauncherPanel {
        let hosting = NSHostingView(
            rootView: QuickLauncherView().environment(\.appEnvironment, environmentProvider())
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 400)
        // The panel sizes itself to the content: an empty query shows a bare search field, and
        // the window should not reserve space for results that are not there.
        hosting.autoresizingMask = [.width, .height]

        let panel = QuickLauncherPanel(contentView: hosting)

        // Dismiss on focus loss, the behaviour every launcher on the platform has. Clicking away
        // should close it rather than leaving a floating panel stranded over another app.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }

        return panel
    }

    /// Supplies the environment to the hosted SwiftUI tree. Assigned by `AppEnvironment` after
    /// construction, breaking the cycle between the environment and a service it owns.
    var environmentProvider: () -> AppEnvironment = {
        fatalError("QuickLauncherController.environmentProvider was never configured")
    }

    deinit {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
    }
}

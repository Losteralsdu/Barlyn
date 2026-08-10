import SwiftUI

@main
struct BarlynApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The single owner of every service. Held by the `App` value so its lifetime matches the
    /// process; feature code receives it through the SwiftUI environment, never as a global.
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        // Phase 1 ships a plain window that renders the foundation's live state. Phase 2 replaces
        // this as the primary surface with a `MenuBarExtra` and demotes the window to the
        // dashboard.
        Window("Barlyn", id: WindowID.dashboard.rawValue) {
            FoundationStatusView()
                .environment(\.appEnvironment, environment)
                .task { await environment.bootstrap() }
                .preferredColorScheme(environment.preferences[PreferenceKeys.appearance].colorScheme)
        }
        .defaultSize(width: 520, height: 480)
        .windowResizability(.contentMinSize)
    }
}

/// Stable identifiers for scenes, so `openWindow(id:)` calls never rely on string literals.
nonisolated enum WindowID: String {
    case dashboard
    case quickLauncher
    case onboarding
}

extension AppearancePreference {
    /// `nil` means "follow the system", which is what SwiftUI expects for an unset override.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

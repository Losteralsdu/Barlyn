import SwiftUI

@main
struct BarlynApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The single owner of every service. Held by the `App` value so its lifetime matches the
    /// process; feature code receives it through the SwiftUI environment, never as a global.
    @State private var environment: AppEnvironment

    init() {
        let environment = AppEnvironment.live()
        _environment = State(initialValue: environment)

        // Bootstrapping is started here rather than from a view's `.task`. The menu bar label is
        // the app's primary surface and may never be opened, and a `MenuBarExtra` label is not a
        // dependable place to run one-time lifecycle work — but sampling still has to start.
        Task { await environment.bootstrap() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(\.appEnvironment, environment)
        } label: {
            MenuBarLabelView()
                .environment(\.appEnvironment, environment)
        }
        // `.window` gives a panel that can host arbitrary SwiftUI rather than a list of menu
        // items, which is what the metric rows need.
        .menuBarExtraStyle(.window)

        Window("Barlyn", id: WindowID.dashboard.rawValue) {
            DashboardView()
                .environment(\.appEnvironment, environment)
                .preferredColorScheme(environment.preferences[PreferenceKeys.appearance].colorScheme)
        }
        .defaultSize(width: 520, height: 480)
        .windowResizability(.contentMinSize)
        // A menu bar app must not throw a window on screen at login. The dashboard opens on
        // request from the panel instead.
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(\.appEnvironment, environment)
                .preferredColorScheme(environment.preferences[PreferenceKeys.appearance].colorScheme)
        }
    }
}

/// Stable identifiers for scenes, so `openWindow(id:)` calls never rely on string literals.
nonisolated enum WindowID: String {
    case dashboard
    case quickLauncher
    case onboarding
}

nonisolated extension AppearancePreference {
    /// `nil` means "follow the system", which is what SwiftUI expects for an unset override.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

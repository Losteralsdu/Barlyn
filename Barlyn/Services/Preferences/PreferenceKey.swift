import Foundation

/// A typed, defaulted preference.
///
/// Pairing the name with its type and default in one value means a preference can never be read
/// with the wrong type or with an inconsistent default at different call sites.
nonisolated struct PreferenceKey<Value: Codable & Sendable>: Sendable {
    let name: String
    let defaultValue: Value

    init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

/// The catalogue of persisted settings.
///
/// Feature modules add their keys here rather than inventing string literals locally, so the
/// full persisted surface of the app is greppable in one place.
nonisolated enum PreferenceKeys {
    // MARK: General
    static let hasCompletedOnboarding = PreferenceKey("general.hasCompletedOnboarding", default: false)
    static let appearance = PreferenceKey("general.appearance", default: AppearancePreference.system)

    // MARK: Menu bar
    /// Order matters and is user-controlled, hence an array rather than a set.
    static let menuBarMetrics = PreferenceKey<[MetricIdentifier]>(
        "menuBar.metrics",
        default: [.cpuUsage, .memoryUsage]
    )
    /// Seconds. Applied as a `MetricSampler` interval override and clamped by
    /// `AppConfiguration`, so a corrupt value cannot make the app poll faster than the floor.
    static let menuBarUpdateInterval = PreferenceKey("menuBar.updateIntervalSeconds", default: 2.0)
    static let menuBarStyle = PreferenceKey("menuBar.style", default: MenuBarStyle.compact)

    // MARK: Dashboard
    /// Metrics the user has explicitly hidden. A hide-list rather than a show-list, so a newly
    /// added provider appears on the dashboard automatically instead of staying invisible until
    /// the user discovers it — the same "add a provider, it shows up everywhere" promise the
    /// metric system makes elsewhere.
    static let dashboardHiddenMetrics = PreferenceKey<[MetricIdentifier]>(
        "dashboard.hiddenMetrics",
        default: []
    )
    /// Explicit card order. Metrics absent from this list sort after it, by category.
    static let dashboardOrder = PreferenceKey<[MetricIdentifier]>("dashboard.order", default: [])
    static let dashboardShowsCharts = PreferenceKey("dashboard.showsCharts", default: true)

    // MARK: Quick Launcher
    /// Option+Space by default. Command+Space is deliberately avoided: Spotlight owns it, and
    /// Carbon reports registering it as a success while the keystroke never actually arrives.
    static let launcherHotkey = PreferenceKey("launcher.hotkey", default: KeyCombination.optionSpace)
    static let launcherEnabled = PreferenceKey("launcher.enabled", default: true)

    // MARK: Clipboard
    /// Whether history is being recorded. This is the user-facing pause switch, and when off the
    /// polling task is torn down rather than merely ignored.
    static let clipboardEnabled = PreferenceKey("clipboard.enabled", default: true)
    static let clipboardHistoryLimit = PreferenceKey("clipboard.historyLimit", default: 100)
    /// Seconds. macOS has no pasteboard-change notification, so this is a poll. A `changeCount`
    /// read measured 0.73 µs on the development Mac, so this is a responsiveness knob, not an
    /// energy one.
    static let clipboardPollInterval = PreferenceKey("clipboard.pollIntervalSeconds", default: 0.5)
}

/// How much each metric shows in the menu bar itself, where horizontal space is scarce.
nonisolated enum MenuBarStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Values only: `24%  49%`.
    case compact
    /// Short name plus value: `CPU 24%  RAM 49%`.
    case labelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: "Compact"
        case .labelled: "With Labels"
        }
    }
}

/// User-selectable appearance, mapped to `NSAppearance` at the UI boundary.
nonisolated enum AppearancePreference: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

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

    // MARK: Menu bar (Phase 2)
    /// Order matters and is user-controlled, hence an array rather than a set.
    static let menuBarMetrics = PreferenceKey<[MetricIdentifier]>(
        "menuBar.metrics",
        default: [.cpuUsage, .memoryUsage]
    )
    static let menuBarUpdateInterval = PreferenceKey("menuBar.updateIntervalSeconds", default: 2.0)
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

import Foundation

/// Common shape for every domain error in Barlyn.
///
/// Two distinct audiences need two distinct strings, and conflating them is how apps end up
/// showing `kIOReturnNotPrivileged (0xe00002c1)` to end users:
///
/// - `userMessage` is shown in the UI. Plain language, no error codes, no framework names.
/// - `diagnosticDescription` goes to Unified Logging and the Settings › Advanced diagnostics
///   pane. It may contain codes, keys and API names.
/// `Codable` because errors travel inside `MetricReading.unavailable`, and readings are
/// persisted (Phase 4 metric history) and cached. Every conformer's associated values must
/// therefore stay Codable — a good constraint anyway, since it rules out stuffing opaque
/// `NSError`s into the domain error types.
nonisolated protocol BarlynError: Error, Hashable, Sendable, Codable {
    var userMessage: String { get }
    var diagnosticDescription: String { get }
    /// When true, the user can do something about it (grant a permission, change a setting)
    /// and the UI should offer that affordance rather than a bare error string.
    var isActionable: Bool { get }
}

nonisolated extension BarlynError {
    var isActionable: Bool { false }
    var diagnosticDescription: String { userMessage }
}

/// System permissions Barlyn may need. Declared centrally so permission state never has to be
/// re-derived from scattered `AXIsProcessTrusted()` calls inside views.
nonisolated enum PermissionKind: String, Sendable, Hashable, CaseIterable, Codable {
    /// Required to read and move other applications' windows via the Accessibility API.
    case accessibility
    /// Required to observe key events globally (used by some future shortcut scopes).
    case inputMonitoring

    var displayName: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    /// Deep link into the relevant System Settings pane.
    var settingsURL: URL? {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .inputMonitoring:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }
    }
}

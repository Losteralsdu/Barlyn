import Foundation

/// Ordinal metric states.
///
/// Some genuinely useful system readings are named levels rather than magnitudes. Rather than
/// giving them a parallel display pipeline, they travel as ordinary `MetricValue`s carrying an
/// ordinal unit, and `MetricFormatter` renders the name. That keeps one path from provider to UI
/// for every metric, which is the property the whole metric system is built around.
///
/// These live in Core because the formatter needs them and Core must not depend on Services.

/// macOS thermal pressure, from the public `ProcessInfo.thermalState` API.
nonisolated enum ThermalPressureLevel: Int, Sendable, Hashable, CaseIterable, Codable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    var displayName: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default:
            // A future OS could add a level. Reporting the highest known severity is the safe
            // direction to round an unknown thermal state.
            self = .critical
        }
    }
}

/// Distinct battery states the UI must be able to tell apart.
///
/// "Plugged in but not charging" is a real, common state (charge limit, thermal hold) and is
/// kept separate from "fully charged" rather than collapsed into it.
nonisolated enum BatteryState: Int, Sendable, Hashable, CaseIterable, Codable {
    case discharging = 0
    case charging = 1
    case full = 2
    case connectedNotCharging = 3

    var displayName: String {
        switch self {
        case .discharging: "On Battery"
        case .charging: "Charging"
        case .full: "Fully Charged"
        case .connectedNotCharging: "Plugged In"
        }
    }
}

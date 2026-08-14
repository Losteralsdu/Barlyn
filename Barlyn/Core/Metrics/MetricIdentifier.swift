import Foundation

/// Stable, persistable name for a metric.
///
/// A string-backed identifier rather than an enum on purpose: menu bar layout, dashboard widget
/// order and Quick Launcher results are all persisted by identifier. An enum would make adding a
/// metric a breaking change for every stored preference, and would force every future provider
/// to be declared in this one file — exactly the coupling the metric system exists to avoid.
nonisolated struct MetricIdentifier: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    var description: String { rawValue }
}

// `nonisolated` is required, not decorative: the project builds with
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so an unmarked extension would make these constants
// main-actor-isolated and unusable from the nonisolated contexts that reference them.
nonisolated extension MetricIdentifier {
    // Phase 1
    static let uptime = MetricIdentifier("system.uptime")

    // Phase 3
    static let cpuUsage = MetricIdentifier("cpu.usage")
    static let memoryUsage = MetricIdentifier("memory.usage")
    static let batteryPower = MetricIdentifier("battery.power")
    /// Adapter draw for the whole machine — a different quantity from `batteryPower`.
    static let systemPowerInput = MetricIdentifier("power.systemInput")
    static let cpuTemperature = MetricIdentifier("cpu.temperature")
    static let thermalPressure = MetricIdentifier("thermal.pressure")
    static let loadAverage = MetricIdentifier("system.loadAverage")
}

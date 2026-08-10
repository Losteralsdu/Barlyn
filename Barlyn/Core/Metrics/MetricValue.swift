import Foundation

/// A magnitude paired with its unit.
nonisolated struct MetricValue: Sendable, Hashable, Codable {
    let magnitude: Double
    let unit: MetricUnit

    init(_ magnitude: Double, _ unit: MetricUnit) {
        self.magnitude = magnitude
        self.unit = unit
    }

    /// True when the magnitude is finite and inside the unit's plausible range.
    /// Providers reading undocumented sensors must gate on this before publishing a value —
    /// publishing an implausible number is the "fabricated metric" failure mode.
    var isPlausible: Bool {
        guard magnitude.isFinite else { return false }
        guard let range = unit.plausibleRange else { return true }
        return range.contains(magnitude)
    }

    static func percent(_ value: Double) -> MetricValue { .init(value, .percent) }
    static func celsius(_ value: Double) -> MetricValue { .init(value, .celsius) }
    static func watts(_ value: Double) -> MetricValue { .init(value, .watts) }
    static func bytes(_ value: UInt64) -> MetricValue { .init(Double(value), .bytes) }
    static func seconds(_ value: Double) -> MetricValue { .init(value, .seconds) }
}

/// One labelled part of a composite reading.
///
/// Lets a single metric carry its own breakdown without a bespoke model per metric: CPU usage
/// ships `user` / `system` / `idle`, memory ships `used` / `total` / `wired` / `compressed`.
/// The dashboard can render components generically; the menu bar ignores them.
nonisolated struct MetricComponent: Sendable, Hashable, Codable, Identifiable {
    /// Stable key for lookup and persistence, e.g. `"user"`, `"wired"`.
    let id: String
    /// Human-readable label, e.g. `"User"`.
    let label: String
    let value: MetricValue

    init(id: String, label: String, value: MetricValue) {
        self.id = id
        self.label = label
        self.value = value
    }
}

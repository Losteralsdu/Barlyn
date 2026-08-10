import Foundation

/// Supplies one metric.
///
/// The whole extensibility contract of the app lives here. A provider knows how to talk to a
/// system API; it knows nothing about SwiftUI, preferences or scheduling. Conversely no UI knows
/// which API backs a metric. Adding a metric means: implement this, register it, done.
///
/// Providers are `Sendable` and sampled off the main actor — mach and IOKit calls must never
/// block the UI. Implementations that need mutable state (delta-based metrics such as CPU usage,
/// which must retain the previous tick counts) should be `actor`s.
nonisolated protocol MetricProvider: Sendable {
    var descriptor: MetricDescriptor { get }

    /// Cheap, cached check for whether this metric can work on this machine at all.
    /// Called once at registration so unsupported metrics are hidden rather than shown broken.
    func isSupported() async -> Bool

    /// Takes one measurement.
    ///
    /// Returning `.unavailable` and throwing are both legitimate: throw for an unexpected
    /// failure the sampler should log, return `.unavailable` for an expected, explainable
    /// absence (sensor idle, no battery installed).
    func read() async throws(MetricError) -> MetricReading
}

nonisolated extension MetricProvider {
    func isSupported() async -> Bool { true }

    var id: MetricIdentifier { descriptor.id }
}

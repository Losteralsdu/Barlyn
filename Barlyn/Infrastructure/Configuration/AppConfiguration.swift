import Foundation

/// Tuning constants that affect runtime cost.
///
/// Barlyn runs continuously, so every polling interval is a battery decision. Keeping the
/// bounds in one place makes it possible to reason about worst-case wakeups without auditing
/// every provider.
nonisolated enum AppConfiguration {
    /// Hard floor for metric sampling. No provider or user preference may sample faster than
    /// this: sub-second polling of `host_processor_info` / SMC costs measurably more energy
    /// than it delivers in perceived responsiveness.
    static let minimumSampleInterval: Duration = .milliseconds(500)

    /// Ceiling used when a user preference is unset or nonsensical.
    static let maximumSampleInterval: Duration = .seconds(60)

    /// Default cadence for providers that do not state a preference.
    static let defaultSampleInterval: Duration = .seconds(2)

    /// Clamps an interval into the supported range.
    static func clampSampleInterval(_ interval: Duration) -> Duration {
        min(max(interval, minimumSampleInterval), maximumSampleInterval)
    }
}

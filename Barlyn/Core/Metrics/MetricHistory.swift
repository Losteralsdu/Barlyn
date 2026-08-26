import Foundation

/// One point in a metric's recent history.
///
/// Deliberately leaner than `MetricSnapshot`: only the headline magnitude and a timestamp, no
/// components. A chart needs a scalar series, and retaining every breakdown for every sample
/// would multiply the memory cost of history by the number of components for no visible gain.
nonisolated struct HistoricalSample: Sendable, Hashable {
    let magnitude: Double
    let timestamp: Date
}

/// Bounded, in-memory recent history for charting.
///
/// **Deliberately not persistent.** The specification asks for live values now with room for
/// history later, so this keeps a short rolling window in memory and writes nothing to disk.
/// Adding real retention later means giving this a storage backend; nothing above it changes.
///
/// **History is discarded when sampling stops**, mirroring `MetricSampler`'s stale-value policy.
/// Keeping it would let a chart draw a continuous line across a period when nothing was
/// measured, which reads as data that was never collected.
@MainActor
@Observable
final class MetricHistory {
    /// Samples retained per metric. At the 2 s default cadence this is roughly four minutes —
    /// enough to show a trend, small enough that the cost is irrelevant even for many metrics.
    static let capacity = 120

    private var series: [MetricIdentifier: [HistoricalSample]] = [:]

    init() {}

    func record(_ reading: MetricReading, for id: MetricIdentifier) {
        // Only real measurements are recorded. An unavailable reading is not a zero, and
        // charting it as one would invent a data point.
        guard let snapshot = reading.snapshot else { return }

        var samples = series[id] ?? []
        samples.append(
            HistoricalSample(magnitude: snapshot.value.magnitude, timestamp: snapshot.timestamp)
        )
        // A plain array trim rather than a ring buffer: at 120 elements the copy is trivial and
        // the code stays obvious.
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
        series[id] = samples
    }

    func samples(for id: MetricIdentifier) -> [HistoricalSample] {
        series[id] ?? []
    }

    func clear(_ id: MetricIdentifier) {
        series.removeValue(forKey: id)
    }

    func clearAll() {
        series.removeAll()
    }
}

import Charts
import SwiftUI

/// Compact trend chart for a metric's recent samples.
///
/// Swift Charts rather than a hand-drawn `Path`: it is an Apple framework (no dependency added),
/// and it brings axis scaling and VoiceOver chart descriptions that a bespoke shape would have
/// to reimplement badly.
///
/// Renders nothing until at least two samples exist — a single point is not a trend, and drawing
/// a flat line through it would imply stability that has not been observed.
struct MetricChartView: View {
    let samples: [HistoricalSample]
    let unit: MetricUnit

    var body: some View {
        if samples.count < 2 {
            // Reserves the same height so a card does not resize as its first samples arrive.
            Color.clear.frame(height: 32)
        } else {
            Chart(samples, id: \.timestamp) { sample in
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Value", sample.magnitude)
                )
                .foregroundStyle(.tint.opacity(0.15))

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Value", sample.magnitude)
                )
                .foregroundStyle(.tint)
                .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: domain)
            .frame(height: 32)
            .accessibilityLabel("Recent trend")
            .accessibilityValue(trendDescription)
        }
    }

    /// Percentages are pinned to 0–100 so a card showing 3 % CPU does not draw a dramatic
    /// mountain range out of noise. Unbounded units auto-scale with padding.
    private var domain: ClosedRange<Double> {
        if unit == .percent { return 0...100 }

        let magnitudes = samples.map(\.magnitude)
        let low = magnitudes.min() ?? 0
        let high = magnitudes.max() ?? 1
        guard high > low else { return (low - 1)...(high + 1) }
        let padding = (high - low) * 0.1
        return (low - padding)...(high + padding)
    }

    private var trendDescription: String {
        guard let first = samples.first?.magnitude, let last = samples.last?.magnitude else { return "" }
        if last > first { return "rising" }
        if last < first { return "falling" }
        return "steady"
    }
}

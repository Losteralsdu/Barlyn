import SwiftUI

/// The always-visible menu bar content.
///
/// Deliberately spare. Menu bar width is shared with every other app on the system, so this
/// shows only what the user asked for, in their order, and falls back to the app glyph when
/// nothing is selected rather than rendering an empty, unclickable gap.
struct MenuBarLabelView: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        let metrics = environment.menuBarConfiguration.visibleMetrics

        if metrics.isEmpty {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
        } else {
            // Monospaced digits stop the item resizing on every sample, which would jitter
            // every other menu bar item to its left.
            Text(labelText(for: metrics))
                .font(.system(size: 12).monospacedDigit())
        }
    }

    private func labelText(for metrics: [MetricDescriptor]) -> String {
        let style = environment.menuBarConfiguration.style
        return metrics.map { descriptor in
            let reading = environment.metricSampler.reading(for: descriptor.id)
            let value = environment.metricFormatter.string(for: reading, style: .compact)
            return style == .labelled ? "\(descriptor.shortName) \(value)" : value
        }
        .joined(separator: "  ")
    }
}

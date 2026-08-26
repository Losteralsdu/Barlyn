import SwiftUI

/// Reusable dashboard tile for any metric.
///
/// Like every other Barlyn surface it is written purely against `MetricDescriptor` and
/// `MetricReading`, so it renders a metric added years from now without modification.
struct MetricCard: View {
    let descriptor: MetricDescriptor
    let reading: MetricReading
    let samples: [HistoricalSample]
    let formatter: MetricFormatter
    let showsChart: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text(formatter.string(for: reading, style: .detailed))
                .font(.system(size: 30, weight: .medium).monospacedDigit())
                .foregroundStyle(reading.isAvailable ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())

            if showsChart {
                MetricChartView(samples: samples, unit: descriptor.unit)
            }

            if let message = unavailableMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !primaryComponents.isEmpty {
                componentGrid
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
        .overlay(alignment: .topTrailing) { provenanceBadge }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(descriptor.displayName)
        .accessibilityValue(formatter.string(for: reading, style: .detailed))
    }

    private var header: some View {
        Label(descriptor.displayName, systemImage: descriptor.symbolName)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    /// A value from an undocumented interface is marked on the card itself, not buried in
    /// Settings — the caveat belongs next to the number it qualifies.
    @ViewBuilder
    private var provenanceBadge: some View {
        if let caveat = descriptor.provenance.caveatText {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(12)
                .help(caveat)
                .accessibilityLabel("Measurement caveat")
                .accessibilityValue(caveat)
        }
    }

    private var unavailableMessage: String? {
        guard case .unavailable(let reason) = reading else { return nil }
        return reason.userMessage
    }

    /// The first few components, so a card stays a card rather than becoming a table. The full
    /// breakdown belongs in a detail view, not here.
    private var primaryComponents: [MetricComponent] {
        Array((reading.snapshot?.components ?? []).prefix(4))
    }

    private var componentGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            ForEach(Array(stride(from: 0, to: primaryComponents.count, by: 2)), id: \.self) { index in
                GridRow {
                    componentCell(primaryComponents[index])
                    if index + 1 < primaryComponents.count {
                        componentCell(primaryComponents[index + 1])
                    }
                }
            }
        }
    }

    private func componentCell(_ component: MetricComponent) -> some View {
        HStack(spacing: 4) {
            Text(component.label)
                .foregroundStyle(.secondary)
            Text(formatter.string(for: component.value, style: .compact))
                .monospacedDigit()
        }
        .font(.caption)
    }
}

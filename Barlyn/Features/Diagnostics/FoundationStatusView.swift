import SwiftUI

/// Phase 1 verification surface.
///
/// Not a product screen. It renders whatever the registry contains, driven entirely by
/// `MetricDescriptor` and `MetricFormatter`, which is how the foundation demonstrates its own
/// central claim: no view knows the name of any specific metric. Phase 4 replaces this with the
/// real dashboard; the data flow it exercises stays.
struct FoundationStatusView: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if environment.metricRegistry.descriptors.isEmpty {
                    ContentUnavailableView(
                        "No Metrics Registered",
                        systemImage: "gauge.with.dots.needle.bottom.50percent",
                        description: Text("Metric providers are registered at launch.")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(environment.metricRegistry.descriptors) { descriptor in
                        MetricRow(
                            descriptor: descriptor,
                            reading: environment.metricSampler.reading(for: descriptor.id),
                            formatter: environment.metricFormatter
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 420, minHeight: 360)
        .task {
            // Declare demand for everything registered, then release it when this view goes
            // away — the same contract the menu bar and dashboard will use.
            let all = Set(environment.metricRegistry.descriptors.map(\.id))
            environment.metricSampler.setDemand(all, for: .diagnostics)
        }
        .onDisappear {
            environment.metricSampler.clearDemand(for: .diagnostics)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Barlyn")
                .font(.largeTitle.weight(.semibold))
            Text("Foundation \(AppInfo.versionDescription) · \(environment.metricRegistry.count) metrics registered")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Generic renderer for any metric. Adding a metric requires no change here.
private struct MetricRow: View {
    let descriptor: MetricDescriptor
    let reading: MetricReading
    let formatter: MetricFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(descriptor.displayName, systemImage: descriptor.symbolName)
                    .font(.headline)
                Spacer(minLength: 16)
                Text(formatter.string(for: reading, style: .detailed))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(reading.isAvailable ? .primary : .secondary)
            }

            if let components = reading.snapshot?.components, !components.isEmpty {
                HStack(spacing: 16) {
                    ForEach(components) { component in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(component.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatter.string(for: component.value, style: .detailed))
                                .font(.callout.monospacedDigit())
                        }
                    }
                }
            }

            if case .unavailable(let reason) = reading, let message = reason.userMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Surfacing provenance is a product requirement, not a debug affordance: a value
            // read from an undocumented interface must never look as authoritative as one from
            // a supported API.
            if let caveat = descriptor.provenance.caveatText {
                Label(caveat, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(descriptor.displayName)
        .accessibilityValue(formatter.string(for: reading, style: .detailed))
    }
}

#Preview {
    FoundationStatusView()
        .environment(\.appEnvironment, .ephemeral())
}

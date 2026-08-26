import AppKit
import SwiftUI

/// The panel shown when the menu bar item is clicked.
///
/// Shows every registered metric, not just the ones in the menu bar: the label is the glanceable
/// subset, this is the full picture. Written against `MetricDescriptor` alone, so new providers
/// appear here with no edit.
struct MenuBarContentView: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groupedDescriptors), id: \.category) { group in
                Section {
                    ForEach(group.descriptors) { descriptor in
                        MenuBarMetricRow(
                            descriptor: descriptor,
                            reading: environment.metricSampler.reading(for: descriptor.id),
                            formatter: environment.metricFormatter
                        )
                    }
                } header: {
                    Text(group.category.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                }
            }

            Divider().padding(.vertical, 8)

            HStack(spacing: 8) {
                Button("Dashboard") {
                    // With no Dock icon the app is not activated by the click that opened this
                    // panel, so a new window would otherwise appear behind the frontmost app.
                    NSApp.activate()
                    openWindow(id: WindowID.dashboard.rawValue)
                }
                SettingsLink { Text("Settings…") }
                    .onHover { _ in NSApp.activate() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.accessoryBar)
        }
        .padding(12)
        .frame(width: 300)
        .task {
            // Demand for the full set lasts only while the panel is open; the menu bar label's
            // own subset is managed separately and persists.
            environment.metricSampler.setDemand(
                Set(environment.metricRegistry.descriptors.map(\.id)),
                for: .menuBarPopover
            )
        }
        .onDisappear {
            environment.metricSampler.clearDemand(for: .menuBarPopover)
        }
    }

    private var groupedDescriptors: [(category: MetricCategory, descriptors: [MetricDescriptor])] {
        let descriptors = environment.metricRegistry.descriptors
        return MetricCategory.allCases
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { category in
                let matching = descriptors.filter { $0.category == category }
                return matching.isEmpty ? nil : (category, matching)
            }
    }
}

/// One compact row: name on the left, value on the right.
private struct MenuBarMetricRow: View {
    let descriptor: MetricDescriptor
    let reading: MetricReading
    let formatter: MetricFormatter

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: descriptor.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(descriptor.displayName)
                .lineLimit(1)
            // A value read from an undocumented interface is marked even here, where space is
            // tightest — the caveat is part of the number, not an optional extra.
            if descriptor.provenance.isFullySupported == false {
                Image(systemName: "questionmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help(descriptor.provenance.caveatText ?? "")
            }
            Spacer(minLength: 8)
            Text(formatter.string(for: reading, style: .compact))
                .monospacedDigit()
                .foregroundStyle(reading.isAvailable ? .primary : .secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(descriptor.displayName)
        .accessibilityValue(formatter.string(for: reading, style: .detailed))
    }
}

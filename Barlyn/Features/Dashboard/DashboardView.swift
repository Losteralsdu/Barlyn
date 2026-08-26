import SwiftUI

/// The main window: a live card per metric.
///
/// Replaces `FoundationStatusView`, the Phase 1 scaffold. The data flow is unchanged — declare
/// demand on appear, release it on disappear — because that contract was designed for exactly
/// this and did not need revisiting for a real UI.
struct DashboardView: View {
    @Environment(\.appEnvironment) private var environment

    /// Cards reflow between one and three columns with the window; each keeps a readable width
    /// rather than stretching to fill an arbitrarily wide window.
    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 420), spacing: 16)]

    var body: some View {
        ScrollView {
            let metrics = environment.dashboardConfiguration.visibleMetrics

            if metrics.isEmpty {
                ContentUnavailableView {
                    Label("No Metrics Shown", systemImage: "square.grid.2x2")
                } description: {
                    Text("Every metric is hidden. Choose which to display in Settings › Dashboard.")
                } actions: {
                    SettingsLink { Text("Open Settings") }
                }
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(metrics) { descriptor in
                        MetricCard(
                            descriptor: descriptor,
                            reading: environment.metricSampler.reading(for: descriptor.id),
                            samples: environment.metricSampler.history.samples(for: descriptor.id),
                            formatter: environment.metricFormatter,
                            showsChart: environment.dashboardConfiguration.showsCharts
                        )
                    }
                }
                .padding(16)
                .animation(.default, value: metrics.map(\.id))
            }
        }
        .frame(minWidth: 380, minHeight: 320)
        .navigationTitle("Barlyn")
        .task(id: visibleIdentifiers) {
            // `task(id:)` rather than `task`: when a late-registering provider (ADR-008) or a
            // settings change alters the card list, demand must follow it.
            environment.metricSampler.setDemand(visibleIdentifiers, for: .dashboard)
        }
        .onDisappear {
            environment.metricSampler.clearDemand(for: .dashboard)
        }
    }

    private var visibleIdentifiers: Set<MetricIdentifier> {
        Set(environment.dashboardConfiguration.visibleMetrics.map(\.id))
    }
}

#Preview {
    DashboardView()
        .environment(\.appEnvironment, .ephemeral())
}

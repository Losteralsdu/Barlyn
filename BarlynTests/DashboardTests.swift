import Foundation
import Testing
@testable import Barlyn

@Suite("Metric history")
@MainActor
struct MetricHistoryTests {

    private func snapshot(_ magnitude: Double) -> MetricReading {
        .available(MetricSnapshot(value: .percent(magnitude)))
    }

    @Test("Records only real measurements")
    func ignoresUnavailableReadings() {
        let history = MetricHistory()
        let id = MetricIdentifier("test.a")

        history.record(snapshot(10), for: id)
        // An unavailable reading is not a zero. Charting it as one would invent a data point.
        history.record(.unavailable(.failed(.timedOut)), for: id)
        history.record(.notYetSampled, for: id)

        #expect(history.samples(for: id).map(\.magnitude) == [10])
    }

    @Test("Retains only the most recent samples")
    func boundedCapacity() {
        let history = MetricHistory()
        let id = MetricIdentifier("test.a")

        for value in 0..<(MetricHistory.capacity + 50) {
            history.record(snapshot(Double(value % 100)), for: id)
        }

        let samples = history.samples(for: id)
        #expect(samples.count == MetricHistory.capacity)
        // Oldest samples are dropped, not newest — the window must slide forward.
        let expectedFirst = Double((MetricHistory.capacity + 50 - MetricHistory.capacity) % 100)
        #expect(samples.first?.magnitude == expectedFirst)
    }

    @Test("Clearing removes a metric's series without touching others")
    func clearIsScoped() {
        let history = MetricHistory()
        let a = MetricIdentifier("test.a")
        let b = MetricIdentifier("test.b")
        history.record(snapshot(1), for: a)
        history.record(snapshot(2), for: b)

        history.clear(a)
        #expect(history.samples(for: a).isEmpty)
        #expect(history.samples(for: b).count == 1)
    }

    @Test("Releasing demand discards history along with the value")
    func historyDroppedWithDemand() async throws {
        let registry = MetricRegistry()
        let provider = MockMetricProvider(id: MetricIdentifier("test.history"))
        registry.register(provider)

        let sampler = MetricSampler(registry: registry)
        sampler.setDemand([provider.id], for: .dashboard)

        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline, sampler.history.samples(for: provider.id).isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!sampler.history.samples(for: provider.id).isEmpty)

        sampler.clearDemand(for: .dashboard)
        // A chart spanning a sampling gap would draw a line across a period never measured.
        #expect(sampler.history.samples(for: provider.id).isEmpty)
    }
}

@Suite("Dashboard configuration")
@MainActor
struct DashboardConfigurationTests {

    private func makeEnvironment() -> AppEnvironment {
        let environment = AppEnvironment.ephemeral()
        for name in ["a", "b", "c"] {
            environment.metricRegistry.register(MockMetricProvider(id: MetricIdentifier(name)))
        }
        return environment
    }

    @Test("Everything registered is visible by default")
    func visibleByDefault() {
        let environment = makeEnvironment()
        #expect(environment.dashboardConfiguration.visibleMetrics.map(\.id.rawValue) == ["a", "b", "c"])
        #expect(environment.dashboardConfiguration.hiddenMetrics.isEmpty)
    }

    @Test("A newly registered metric appears without the user enabling it")
    func newMetricsAppearAutomatically() {
        let environment = makeEnvironment()
        let config = environment.dashboardConfiguration
        config.move(MetricIdentifier("c"), by: -1)   // materialises a stored order

        // Simulates a late-registering provider (ADR-008) or one added by a later version.
        environment.metricRegistry.register(MockMetricProvider(id: MetricIdentifier("d")))

        // It must show up, and must not displace the user's existing arrangement.
        #expect(config.visibleMetrics.map(\.id.rawValue) == ["a", "c", "b", "d"])
    }

    @Test("Hiding removes a card and lists it as hidden")
    func hiding() {
        let environment = makeEnvironment()
        let config = environment.dashboardConfiguration

        config.setVisible(false, for: MetricIdentifier("b"))
        #expect(config.visibleMetrics.map(\.id.rawValue) == ["a", "c"])
        #expect(config.hiddenMetrics.map(\.id.rawValue) == ["b"])
        #expect(config.isVisible(MetricIdentifier("b")) == false)

        config.setVisible(true, for: MetricIdentifier("b"))
        #expect(config.visibleMetrics.map(\.id.rawValue) == ["a", "b", "c"])
    }

    @Test("Hiding twice does not duplicate the hide entry")
    func hideIsIdempotent() {
        let environment = makeEnvironment()
        let config = environment.dashboardConfiguration
        config.setVisible(false, for: MetricIdentifier("b"))
        config.setVisible(false, for: MetricIdentifier("b"))
        #expect(environment.preferences[PreferenceKeys.dashboardHiddenMetrics].count == 1)
    }

    @Test("Reordering clamps at both ends")
    func moveClamps() {
        let environment = makeEnvironment()
        let config = environment.dashboardConfiguration

        config.move(MetricIdentifier("a"), by: -1)
        #expect(config.visibleMetrics.map(\.id.rawValue) == ["a", "b", "c"])

        config.move(MetricIdentifier("a"), by: 1)
        #expect(config.visibleMetrics.map(\.id.rawValue) == ["b", "a", "c"])

        config.move(MetricIdentifier("c"), by: 1)
        #expect(config.visibleMetrics.map(\.id.rawValue) == ["b", "a", "c"])
    }

    @Test("Reset restores default visibility and order")
    func resetLayout() {
        let environment = makeEnvironment()
        let config = environment.dashboardConfiguration
        config.setVisible(false, for: MetricIdentifier("a"))
        config.move(MetricIdentifier("c"), by: -1)

        config.resetLayout()
        #expect(config.visibleMetrics.map(\.id.rawValue) == ["a", "b", "c"])
        #expect(config.hiddenMetrics.isEmpty)
    }

    @Test("Layout survives a reopened store")
    func persistence() {
        let storage = InMemoryPreferenceStorage()
        let first = AppEnvironment(preferences: PreferenceStore(storage: storage))
        for name in ["a", "b"] {
            first.metricRegistry.register(MockMetricProvider(id: MetricIdentifier(name)))
        }
        first.dashboardConfiguration.setVisible(false, for: MetricIdentifier("a"))
        first.dashboardConfiguration.setShowsCharts(false)

        let reopened = AppEnvironment(preferences: PreferenceStore(storage: storage))
        for name in ["a", "b"] {
            reopened.metricRegistry.register(MockMetricProvider(id: MetricIdentifier(name)))
        }
        #expect(reopened.dashboardConfiguration.visibleMetrics.map(\.id.rawValue) == ["b"])
        #expect(reopened.dashboardConfiguration.showsCharts == false)
    }
}

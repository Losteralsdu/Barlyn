import Foundation
import Testing
@testable import Barlyn

@Suite("Menu bar configuration")
@MainActor
struct MenuBarConfigurationTests {

    /// Registry containing three stand-in metrics, so ordering and visibility can be tested
    /// without depending on which hardware the test machine actually has.
    private func makeEnvironment() -> AppEnvironment {
        let environment = AppEnvironment.ephemeral()
        for name in ["a", "b", "c"] {
            environment.metricRegistry.register(MockMetricProvider(id: MetricIdentifier(name)))
        }
        return environment
    }

    @Test("Only registered metrics become visible")
    func filtersUnregisteredMetrics() {
        let environment = makeEnvironment()
        // A preference can name a metric whose hardware is absent, or one removed in a later
        // version. Those must be skipped, not shown as permanently broken rows.
        environment.preferences[PreferenceKeys.menuBarMetrics] = [
            MetricIdentifier("a"), MetricIdentifier("nonexistent"), MetricIdentifier("c"),
        ]

        let visible = environment.menuBarConfiguration.visibleMetrics
        #expect(visible.map(\.id.rawValue) == ["a", "c"])
    }

    @Test("Visible order follows the user's order, not registration order")
    func respectsUserOrder() {
        let environment = makeEnvironment()
        environment.preferences[PreferenceKeys.menuBarMetrics] = [
            MetricIdentifier("c"), MetricIdentifier("a"),
        ]
        #expect(environment.menuBarConfiguration.visibleMetrics.map(\.id.rawValue) == ["c", "a"])
    }

    @Test("Adding and removing a metric updates sampler demand")
    func visibilityDrivesDemand() {
        let environment = makeEnvironment()
        let config = environment.menuBarConfiguration
        environment.preferences[PreferenceKeys.menuBarMetrics] = []
        config.apply()
        #expect(environment.metricSampler.activeMetrics.isEmpty)

        config.setVisible(true, for: MetricIdentifier("a"))
        #expect(environment.metricSampler.activeMetrics == [MetricIdentifier("a")])

        config.setVisible(false, for: MetricIdentifier("a"))
        #expect(environment.metricSampler.activeMetrics.isEmpty)
    }

    @Test("Adding a metric twice does not duplicate it")
    func noDuplicates() {
        let environment = makeEnvironment()
        let config = environment.menuBarConfiguration
        environment.preferences[PreferenceKeys.menuBarMetrics] = []

        config.setVisible(true, for: MetricIdentifier("a"))
        config.setVisible(true, for: MetricIdentifier("a"))
        #expect(environment.preferences[PreferenceKeys.menuBarMetrics].count == 1)
    }

    @Test("Moving reorders and clamps at the ends")
    func moveClamps() {
        let environment = makeEnvironment()
        let config = environment.menuBarConfiguration
        environment.preferences[PreferenceKeys.menuBarMetrics] = [
            MetricIdentifier("a"), MetricIdentifier("b"), MetricIdentifier("c"),
        ]

        config.move(MetricIdentifier("c"), by: -1)
        #expect(config.visibleMetrics.map(\.id.rawValue) == ["a", "c", "b"])

        // Moving the first item earlier must be a no-op rather than a crash or a wrap-around.
        config.move(MetricIdentifier("a"), by: -1)
        #expect(config.visibleMetrics.map(\.id.rawValue) == ["a", "c", "b"])

        config.move(MetricIdentifier("b"), by: 1)
        #expect(config.visibleMetrics.map(\.id.rawValue) == ["a", "c", "b"])
    }

    @Test("Update interval is applied to visible metrics and clamped to safe bounds")
    func intervalIsAppliedAndClamped() {
        let environment = makeEnvironment()
        let config = environment.menuBarConfiguration
        let id = MetricIdentifier("a")
        environment.preferences[PreferenceKeys.menuBarMetrics] = [id]

        config.setUpdateInterval(5)
        let descriptor = try! #require(environment.metricRegistry.descriptor(for: id))
        #expect(environment.metricSampler.effectiveInterval(for: descriptor) == .seconds(5))

        // No preference — corrupt, hand-edited or otherwise — may poll faster than the floor.
        config.setUpdateInterval(0.001)
        #expect(
            environment.metricSampler.effectiveInterval(for: descriptor)
                == AppConfiguration.minimumSampleInterval
        )
    }

    @Test("Preferences survive a reopened store")
    func preferencesPersist() {
        let storage = InMemoryPreferenceStorage()
        let environment = AppEnvironment(preferences: PreferenceStore(storage: storage))
        environment.metricRegistry.register(MockMetricProvider(id: MetricIdentifier("a")))
        environment.menuBarConfiguration.setStyle(.labelled)
        environment.menuBarConfiguration.setUpdateInterval(4)

        let reopened = AppEnvironment(preferences: PreferenceStore(storage: storage))
        #expect(reopened.preferences[PreferenceKeys.menuBarStyle] == .labelled)
        #expect(reopened.preferences[PreferenceKeys.menuBarUpdateInterval] == 4)
    }
}

@Suite("Default metric ordering")
@MainActor
struct MetricOrderingTests {

    @Test("Descriptors sort by category regardless of registration wave")
    func categoryOrdering() {
        let registry = MetricRegistry()
        // Deliberately register out of display order, mimicking the late arrival of
        // hardware-probed providers (ADR-008).
        registry.register(UptimeMetricProvider())           // .system
        registry.register(ThermalPressureMetricProvider())  // .thermal
        registry.register(CPUUsageMetricProvider())         // .processor
        registry.register(MemoryMetricProvider())           // .memory

        #expect(
            registry.descriptors.map(\.category) == [.processor, .memory, .thermal, .system]
        )
    }

    @Test("Order within a category stays registration order")
    func stableWithinCategory() {
        let registry = MetricRegistry()
        for name in ["c", "a", "b"] {
            registry.register(MockMetricProvider(id: MetricIdentifier("test.\(name)")))
        }
        #expect(registry.descriptors.map(\.id.rawValue) == ["test.c", "test.a", "test.b"])
    }
}

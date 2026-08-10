import Foundation
import Testing
@testable import Barlyn

@Suite("Metric registry")
@MainActor
struct MetricRegistryTests {

    @Test("Registration exposes the descriptor and provider")
    func registration() {
        let registry = MetricRegistry()
        let provider = MockMetricProvider(id: MetricIdentifier("test.a"))

        #expect(registry.register(provider))
        #expect(registry.count == 1)
        #expect(registry.descriptor(for: provider.id)?.displayName == "Mock test.a")
        #expect(registry.provider(for: provider.id) != nil)
    }

    @Test("Duplicate identifiers are rejected, not silently overwritten")
    func duplicateRejected() {
        let registry = MetricRegistry()
        let id = MetricIdentifier("test.duplicate")

        #expect(registry.register(MockMetricProvider(id: id, unit: .percent)))
        #expect(registry.register(MockMetricProvider(id: id, unit: .celsius)) == false)

        #expect(registry.count == 1)
        // The first registration must win, so ordering of registration cannot change behaviour.
        #expect(registry.descriptor(for: id)?.unit == .percent)
    }

    @Test("Unsupported providers are omitted entirely")
    func unsupportedOmitted() async {
        let registry = MetricRegistry()
        let unsupported = MockMetricProvider(id: MetricIdentifier("test.fan"), supported: false)

        #expect(await registry.registerIfSupported(unsupported) == false)
        #expect(registry.isEmpty)
        #expect(registry.descriptor(for: unsupported.id) == nil)
    }

    @Test("Descriptor order follows registration order")
    func stableOrdering() {
        let registry = MetricRegistry()
        for name in ["c", "a", "b"] {
            registry.register(MockMetricProvider(id: MetricIdentifier("test.\(name)")))
        }
        #expect(registry.descriptors.map(\.id.rawValue) == ["test.c", "test.a", "test.b"])
    }

    @Test("Metrics can be filtered by category")
    func categoryFiltering() {
        let registry = MetricRegistry()
        registry.register(MockMetricProvider(id: MetricIdentifier("test.x")))
        registry.register(UptimeMetricProvider())

        #expect(registry.descriptors(in: .system).count == 2)
        #expect(registry.descriptors(in: .network).isEmpty)
    }
}

@Suite("Metric sampler")
@MainActor
struct MetricSamplerTests {

    @Test("Sampling only runs for metrics a consumer has asked for")
    func demandDrivenSampling() async throws {
        let registry = MetricRegistry()
        let wanted = MockMetricProvider(id: MetricIdentifier("test.wanted"))
        let ignored = MockMetricProvider(id: MetricIdentifier("test.ignored"))
        registry.register(wanted)
        registry.register(ignored)

        let sampler = MetricSampler(registry: registry)
        sampler.setDemand([wanted.id], for: .dashboard)

        try await waitUntil { sampler.reading(for: wanted.id).isAvailable }

        #expect(sampler.reading(for: wanted.id).value == MetricValue(42, .percent))
        #expect(ignored.timesRead == 0)
        #expect(sampler.activeMetrics == [wanted.id])
    }

    @Test("Demand from several consumers is unioned")
    func unionOfDemand() {
        let registry = MetricRegistry()
        let a = MockMetricProvider(id: MetricIdentifier("test.a"))
        let b = MockMetricProvider(id: MetricIdentifier("test.b"))
        registry.register(a)
        registry.register(b)

        let sampler = MetricSampler(registry: registry)
        sampler.setDemand([a.id], for: .menuBar)
        sampler.setDemand([a.id, b.id], for: .dashboard)
        #expect(sampler.activeMetrics == [a.id, b.id])

        // Dropping one consumer must not stop a metric another consumer still needs.
        sampler.clearDemand(for: .dashboard)
        #expect(sampler.activeMetrics == [a.id])
    }

    @Test("Releasing demand discards the value so no stale number can be displayed")
    func staleValuesDropped() async throws {
        let registry = MetricRegistry()
        let provider = MockMetricProvider(id: MetricIdentifier("test.stale"))
        registry.register(provider)

        let sampler = MetricSampler(registry: registry)
        sampler.setDemand([provider.id], for: .menuBar)
        try await waitUntil { sampler.reading(for: provider.id).isAvailable }

        sampler.clearDemand(for: .menuBar)
        #expect(sampler.activeMetrics.isEmpty)
        #expect(sampler.reading(for: provider.id) == .notYetSampled)
    }

    @Test("A failing provider surfaces the reason rather than a fabricated value")
    func failureSurfacesReason() async throws {
        let registry = MetricRegistry()
        let provider = MockMetricProvider(
            id: MetricIdentifier("test.failing"),
            outcome: .failure(.permissionRequired(.accessibility))
        )
        registry.register(provider)

        let sampler = MetricSampler(registry: registry)
        sampler.setDemand([provider.id], for: .dashboard)

        try await waitUntil { sampler.reading(for: provider.id) != .notYetSampled }

        let reading = sampler.reading(for: provider.id)
        #expect(reading.value == nil)
        #expect(reading == .unavailable(.failed(.permissionRequired(.accessibility))))

        guard case .unavailable(let reason) = reading else {
            Issue.record("Expected unavailable reading")
            return
        }
        #expect(reason.isActionable, "A missing permission must be presented as fixable")
    }

    @Test("Requesting an unregistered metric is inert")
    func unregisteredMetricIsInert() {
        let sampler = MetricSampler(registry: MetricRegistry())
        sampler.setDemand([MetricIdentifier("test.missing")], for: .dashboard)
        #expect(sampler.reading(for: MetricIdentifier("test.missing")) == .notYetSampled)
    }
}

/// Polls a main-actor condition instead of sleeping a fixed duration, so tests stay fast and
/// do not flake under load.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(3),
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Condition not met within \(timeout)")
}

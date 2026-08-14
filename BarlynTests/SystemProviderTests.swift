import Foundation
import Testing
@testable import Barlyn

/// These touch real system APIs. They assert on invariants that must hold on any Mac, never on
/// machine-specific numbers, so they stay meaningful on other hardware and in CI.
@Suite("System metric providers")
struct SystemProviderTests {

    @Test("Uptime is positive and consistent with the boot time reported by the kernel")
    func uptimeIsPlausible() async throws {
        let provider = UptimeMetricProvider()
        let reading = try await provider.read()

        let value = try #require(reading.value)
        #expect(value.unit == .seconds)
        #expect(value.magnitude > 0)
        // Wall-clock uptime, so it must be at least the process's own lifetime.
        #expect(value.magnitude >= ProcessInfo.processInfo.systemUptime - 1)
    }

    @Test("Load average returns all three windows")
    func loadAverageComponents() async throws {
        let provider = LoadAverageMetricProvider()
        let reading = try await provider.read()

        let snapshot = try #require(reading.snapshot)
        #expect(snapshot.value.magnitude >= 0)
        #expect(snapshot.components.map(\.id) == ["1m", "5m", "15m"])
        #expect(snapshot.component("1m")?.value == snapshot.value)
    }

    @Test("Both reference providers declare a documented API as their source")
    func provenanceIsPublic() {
        #expect(UptimeMetricProvider().descriptor.provenance.isFullySupported)
        #expect(LoadAverageMetricProvider().descriptor.provenance.isFullySupported)
    }

    @Test("Bootstrapping the live environment registers the Phase 1 providers")
    @MainActor
    func environmentBootstrap() async {
        let environment = AppEnvironment.ephemeral()
        #expect(environment.metricRegistry.isEmpty)

        await environment.bootstrap()

        #expect(environment.isBootstrapped)

        // Assert on identity rather than a count: metrics whose hardware is absent are correctly
        // omitted, so a count would be machine-specific and would break whenever a metric is added.
        for id in [MetricIdentifier.cpuUsage, .memoryUsage, .thermalPressure, .loadAverage, .uptime] {
            #expect(environment.metricRegistry.descriptor(for: id) != nil, "\(id) should always register")
        }

        // Idempotent: SwiftUI may run the bootstrapping `.task` more than once.
        let count = environment.metricRegistry.count
        await environment.bootstrap()
        #expect(environment.metricRegistry.count == count)
    }

    @Test("Slow hardware probing does not block the first wave of registration")
    @MainActor
    func bootstrapDoesNotBlockOnSlowProbes() async {
        let environment = AppEnvironment.ephemeral()

        let clock = ContinuousClock()
        let elapsed = await clock.measure { await environment.bootstrap() }

        // SMC key discovery takes roughly half a second. If it were on the critical path the
        // window would sit empty for that long, so bootstrap must return well before it.
        #expect(elapsed < .milliseconds(250), "bootstrap() took \(elapsed)")
        #expect(environment.metricRegistry.descriptor(for: .cpuUsage) != nil)

        await environment.awaitFullRegistration()
    }

    /// End-to-end through the real composition root: bootstrap, declare demand exactly as the
    /// UI does, and assert that real values from real system APIs arrive and format for display.
    /// This is the path `FoundationStatusView` drives; only SwiftUI rendering is excluded.
    @Test("Full pipeline delivers formatted live values")
    @MainActor
    func livePipeline() async throws {
        let environment = AppEnvironment.ephemeral()
        await environment.bootstrap()

        let allMetrics = Set(environment.metricRegistry.descriptors.map(\.id))
        environment.metricSampler.setDemand(allMetrics, for: .dashboard)

        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if allMetrics.allSatisfy({ environment.metricSampler.reading(for: $0).isAvailable }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        for id in allMetrics {
            let reading = environment.metricSampler.reading(for: id)
            #expect(reading.isAvailable, "\(id) did not produce a value")

            let text = environment.metricFormatter.string(for: reading, style: .detailed)
            #expect(text != MetricFormatter.unavailablePlaceholder)
            #expect(text.isEmpty == false)
        }

        environment.metricSampler.clearDemand(for: .dashboard)
        #expect(environment.metricSampler.activeMetrics.isEmpty)
    }
}

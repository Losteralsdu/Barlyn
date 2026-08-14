import Foundation
import Testing
@testable import Barlyn

/// These exercise real hardware. Assertions are on invariants that must hold on any Mac, never
/// on values specific to the development machine, so they remain valid on other hardware.
@Suite("CPU usage provider")
struct CPUUsageProviderTests {

    @Test("First sample reports not-yet-sampled instead of usage since boot")
    func firstSampleIsHonest() async throws {
        let provider = CPUUsageMetricProvider()
        let first = try await provider.read()

        // Tick counters are cumulative; one sample cannot describe current load. Reporting
        // usage-since-boot here would be a real number presented as something it is not.
        #expect(first == .unavailable(.notYetSampled))
    }

    @Test("Second sample yields usage in range with a consistent breakdown")
    func deltaProducesUsage() async throws {
        let provider = CPUUsageMetricProvider()
        _ = try await provider.read()
        try await Task.sleep(for: .milliseconds(250))
        let second = try await provider.read()

        let snapshot = try #require(second.snapshot)
        #expect(snapshot.value.unit == .percent)
        #expect((0...100).contains(snapshot.value.magnitude))

        let idle = try #require(snapshot.component("idle")?.value.magnitude)
        // The headline figure is defined as 100 - idle; assert the two actually agree.
        #expect(abs(snapshot.value.magnitude - (100 - idle)) < 0.001)

        let user = try #require(snapshot.component("user")?.value.magnitude)
        let system = try #require(snapshot.component("system")?.value.magnitude)
        let nice = try #require(snapshot.component("nice")?.value.magnitude)
        // The four states partition all elapsed ticks, so they must sum to ~100%.
        #expect(abs(user + system + idle + nice - 100) < 0.5)
    }

    @Test("Repeated sampling stays within bounds")
    func repeatedSamplingIsStable() async throws {
        let provider = CPUUsageMetricProvider()
        _ = try await provider.read()

        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(60))
            let reading = try await provider.read()
            if let value = reading.value {
                #expect((0...100).contains(value.magnitude))
            }
        }
    }
}

@Suite("Memory provider")
struct MemoryProviderTests {

    @Test("Reports a used/total breakdown consistent with the headline percentage")
    func breakdownIsConsistent() async throws {
        let reading = try await MemoryMetricProvider().read()
        let snapshot = try #require(reading.snapshot)

        let used = try #require(snapshot.component("used")?.value.magnitude)
        let total = try #require(snapshot.component("total")?.value.magnitude)
        let wired = try #require(snapshot.component("wired")?.value.magnitude)
        let app = try #require(snapshot.component("app")?.value.magnitude)
        let compressed = try #require(snapshot.component("compressed")?.value.magnitude)

        #expect(total == Double(ProcessInfo.processInfo.physicalMemory))
        #expect(used > 0)
        #expect(used < total)

        // The documented definition: used = App Memory + wired + compressed.
        #expect(abs(used - (app + wired + compressed)) < 1)
        #expect(abs(snapshot.value.magnitude - (used / total * 100)) < 0.001)
    }

    @Test("App Memory excludes purgeable pages and cannot underflow")
    func appMemoryIsPurgeableAdjusted() async throws {
        let reading = try await MemoryMetricProvider().read()
        let snapshot = try #require(reading.snapshot)

        let app = try #require(snapshot.component("app")?.value.magnitude)
        let purgeable = try #require(snapshot.component("purgeable")?.value.magnitude)
        let total = try #require(snapshot.component("total")?.value.magnitude)

        // Independently sampled counters can disagree; an unsigned underflow would show up here
        // as an absurd multi-exabyte figure rather than a small number.
        #expect(app >= 0)
        #expect(app < total)
        #expect(purgeable >= 0)
    }

    @Test("Cached files are excluded from used memory")
    func cachedFilesAreNotCountedAsUsed() async throws {
        let reading = try await MemoryMetricProvider().read()
        let snapshot = try #require(reading.snapshot)

        let used = try #require(snapshot.component("used")?.value.magnitude)
        let cached = try #require(snapshot.component("cached")?.value.magnitude)
        let app = try #require(snapshot.component("app")?.value.magnitude)
        let wired = try #require(snapshot.component("wired")?.value.magnitude)
        let compressed = try #require(snapshot.component("compressed")?.value.magnitude)

        // File-backed pages are cache, not usage. Folding them in would inflate the headline
        // figure on any machine that has been reading from disk.
        #expect(cached > 0)
        #expect(abs(used - (app + wired + compressed)) < 1)
    }

    @Test("Page size is read from the kernel, not assumed")
    func pageSizeIsCorrect() async throws {
        // If the provider assumed 4096 on an Apple Silicon Mac (16384), the derived byte totals
        // would be four times too small and 'used' would be an implausible fraction of RAM.
        let reading = try await MemoryMetricProvider().read()
        let snapshot = try #require(reading.snapshot)
        let used = try #require(snapshot.component("used")?.value.magnitude)
        let total = try #require(snapshot.component("total")?.value.magnitude)

        // Any live macOS system has committed well over 1% of RAM.
        #expect(used / total > 0.01)
    }
}

@Suite("Thermal pressure provider")
struct ThermalPressureProviderTests {

    @Test("Reports a known level from the public API")
    func reportsKnownLevel() async throws {
        let reading = try await ThermalPressureMetricProvider().read()
        let value = try #require(reading.value)
        #expect(value.unit == .thermalLevel)
        #expect(ThermalPressureLevel(rawValue: Int(value.magnitude)) != nil)
    }

    @Test("Level maps to a display name, never a bare number")
    func formatsAsName() {
        let formatter = MetricFormatter(locale: Locale(identifier: "en_US_POSIX"))
        #expect(formatter.string(for: .init(0, .thermalLevel)) == "Nominal")
        #expect(formatter.string(for: .init(3, .thermalLevel)) == "Critical")
    }

    @Test("Provenance is a fully supported public API")
    func provenanceIsPublic() {
        #expect(ThermalPressureMetricProvider().descriptor.provenance.isFullySupported)
    }
}

@Suite("SMC service")
struct SMCServiceTests {

    @Test("Wire struct layout matches the AppleSMC user client")
    func wireLayout() {
        // A silent layout change would corrupt every reading rather than fail loudly, so the
        // size is asserted directly.
        #expect(MemoryLayout<SMCKeyData>.stride == 80)
    }

    @Test("Discovered sensors carry a decodable type and plausible values")
    func discoveryAndReads() async throws {
        let smc = SMCService()
        guard await smc.isAvailable() else {
            // A machine without SMC access is a legitimate outcome, not a test failure.
            return
        }

        let sensors = await smc.sensors(in: .cpuPerformanceCore)
        guard !sensors.isEmpty else { return }

        #expect(sensors.allSatisfy { $0.key.count == 4 })
        #expect(sensors.allSatisfy { $0.key.hasPrefix("Tp") })

        let temperatures = await smc.readTemperatures(in: .cpuPerformanceCore)
        #expect(!temperatures.isEmpty, "Sensors were discovered but none produced a usable value")
        // Every value that survives must already be plausible — that filtering is the point.
        #expect(temperatures.allSatisfy { MetricValue.celsius($0).isPlausible })
    }

    @Test("Fan tachometers are distinguished from fan limit and target keys")
    func fanKeyClassification() async throws {
        let smc = SMCService()
        guard await smc.isAvailable() else { return }

        let fans = await smc.sensors(in: .fanSpeed)
        // F0Mn/F0Mx/F0Tg are minimum, maximum and target — not actual speed.
        #expect(fans.allSatisfy { $0.key.hasSuffix("Ac") })
    }
}

@Suite("CPU temperature provider")
struct CPUTemperatureProviderTests {

    @Test("Declares undocumented provenance with a user-facing caveat")
    func provenanceCarriesCaveat() {
        let descriptor = CPUTemperatureMetricProvider(smc: SMCService()).descriptor
        #expect(descriptor.provenance.isFullySupported == false)
        #expect(descriptor.provenance.caveatText != nil)
    }

    @Test("Either reports a plausible temperature or reports unavailable, never a guess")
    func readsOrDeclinesCleanly() async throws {
        let provider = CPUTemperatureMetricProvider(smc: SMCService())

        guard await provider.isSupported() else {
            // Unsupported is a valid outcome; the metric is then simply not registered.
            return
        }

        let reading = try await provider.read()
        let snapshot = try #require(reading.snapshot)
        #expect(snapshot.value.unit == .celsius)
        #expect(snapshot.value.isPlausible)

        let peak = try #require(snapshot.component("peak")?.value.magnitude)
        let count = try #require(snapshot.component("sensors")?.value.magnitude)
        // The mean can never exceed the hottest sensor it was computed from.
        #expect(peak >= snapshot.value.magnitude)
        #expect(count >= 1)
    }
}

@Suite("Power providers")
struct PowerProviderTests {

    @Test("Battery power derives watts from amperage and voltage with a signed convention")
    func batteryPowerDerivation() async throws {
        let service = PowerSourceService()
        guard await service.isBatteryPresent() else { return }

        let snapshot = try await service.snapshot()
        #expect(snapshot.voltage > 0)

        // Sign must follow amperage: negative while discharging, positive while charging.
        let expected = Double(snapshot.amperage) * Double(snapshot.voltage) / 1_000_000
        #expect(snapshot.batteryWatts == expected)
        if snapshot.amperage < 0 { #expect(snapshot.batteryWatts < 0) }
        if snapshot.amperage > 0 { #expect(snapshot.batteryWatts > 0) }
    }

    @Test("Battery state distinguishes plugged-in-not-charging from fully charged")
    func batteryStateResolution() {
        func snapshot(external: Bool, charging: Bool, full: Bool) -> PowerSourceService.Snapshot {
            PowerSourceService.Snapshot(
                amperage: 0, voltage: 12_000, systemPowerInMilliwatts: nil, adapterRatedWatts: nil,
                isExternalConnected: external, isCharging: charging, isFullyCharged: full,
                chargePercent: 80
            )
        }
        #expect(snapshot(external: false, charging: false, full: false).state == .discharging)
        #expect(snapshot(external: true, charging: true, full: false).state == .charging)
        #expect(snapshot(external: true, charging: false, full: true).state == .full)
        // The interesting case: on AC, not charging, not full — a charge limit or thermal hold.
        #expect(snapshot(external: true, charging: false, full: false).state == .connectedNotCharging)
    }

    @Test("System input power is reported as unavailable on battery, not as zero watts")
    func systemPowerOnBattery() async throws {
        let service = PowerSourceService()
        guard await service.isBatteryPresent() else { return }

        let provider = SystemPowerMetricProvider(powerSource: service)
        let snapshot = try await service.snapshot()
        let reading = try await provider.read()

        if snapshot.isExternalConnected {
            let value = try #require(reading.value)
            #expect(value.unit == .watts)
            #expect(value.magnitude > 0)
        } else {
            #expect(reading.isAvailable == false, "On battery there is no adapter draw to report")
        }
    }

    @Test("Battery and system power are separate metrics measuring different quantities")
    func powerMetricsAreDistinct() {
        let service = PowerSourceService()
        let battery = BatteryPowerMetricProvider(powerSource: service).descriptor
        let system = SystemPowerMetricProvider(powerSource: service).descriptor

        #expect(battery.id != system.id)
        #expect(battery.displayName != system.displayName)
    }

    @Test("A snapshot is shared between providers rather than read twice per tick")
    func snapshotIsCached() async throws {
        let service = PowerSourceService()
        guard await service.isBatteryPresent() else { return }

        let first = try await service.snapshot()
        let second = try await service.snapshot()
        // Two reads inside the cache lifetime must be the identical snapshot.
        #expect(first == second)
    }
}

import Foundation
import IOKit
import OSLog

/// Reads the `AppleSmartBattery` IORegistry entry.
///
/// `IOPSCopyPowerSourcesInfo` — the documented power-source API — reports percentage, state and
/// time remaining but **no wattage at all**, which is the number this app needs. The IORegistry
/// entry does expose it, so that is what we read, and the descriptors that depend on it declare
/// `.undocumentedInterface` provenance accordingly.
///
/// Shared by every power metric so that N providers cost one registry traversal per tick rather
/// than N.
actor PowerSourceService {

    /// One coherent view of the battery and adapter.
    ///
    /// Battery power and system input power are deliberately separate fields. They are different
    /// physical quantities — one is energy moving in or out of the cell, the other is what the
    /// wall adapter is delivering — and conflating them is a common way to report a confidently
    /// wrong number.
    nonisolated struct Snapshot: Sendable, Hashable {
        /// Signed milliamps. Negative while discharging.
        let amperage: Int
        /// Battery terminal voltage in millivolts.
        let voltage: Int
        /// Power drawn from the adapter in milliwatts, or `nil` when not reported.
        let systemPowerInMilliwatts: Int?
        /// Adapter's rated maximum in watts, or `nil` on battery.
        let adapterRatedWatts: Int?
        let isExternalConnected: Bool
        let isCharging: Bool
        let isFullyCharged: Bool
        let chargePercent: Int?

        /// Battery-side power in watts: mA × mV = µW, scaled to W.
        /// Positive while charging, negative while discharging.
        var batteryWatts: Double {
            Double(amperage) * Double(voltage) / 1_000_000
        }

        var systemInputWatts: Double? {
            systemPowerInMilliwatts.map { Double($0) / 1_000 }
        }
    }

    /// Registry reads are cheap but not free, and several providers sample at the same cadence.
    /// A TTL shorter than the fastest permitted sampling interval keeps values fresh while
    /// collapsing the duplicate reads within a single tick.
    private static let cacheLifetime: Duration = .milliseconds(250)

    private var cached: (snapshot: Snapshot, timestamp: ContinuousClock.Instant)?

    init() {}

    /// True when this Mac has a battery at all. Desktop Macs return false and the power metrics
    /// are then never registered.
    func isBatteryPresent() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return false }
        IOObjectRelease(service)
        return true
    }

    func snapshot() throws(MetricError) -> Snapshot {
        if let cached, ContinuousClock.now - cached.timestamp < Self.cacheLifetime {
            return cached.snapshot
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            throw MetricError.unsupportedOnThisHardware(detail: "no AppleSmartBattery service")
        }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let properties = unmanaged?.takeRetainedValue() as? [String: Any] else {
            throw MetricError.systemCallFailed(api: "IORegistryEntryCreateCFProperties", code: status)
        }

        let telemetry = properties["PowerTelemetryData"] as? [String: Any]
        let adapter = properties["AdapterDetails"] as? [String: Any]

        let snapshot = Snapshot(
            amperage: properties["Amperage"] as? Int ?? 0,
            voltage: properties["Voltage"] as? Int ?? 0,
            systemPowerInMilliwatts: telemetry?["SystemPowerIn"] as? Int,
            adapterRatedWatts: adapter?["Watts"] as? Int,
            isExternalConnected: properties["ExternalConnected"] as? Bool ?? false,
            isCharging: properties["IsCharging"] as? Bool ?? false,
            isFullyCharged: properties["FullyCharged"] as? Bool ?? false,
            chargePercent: properties["CurrentCapacity"] as? Int
        )

        cached = (snapshot, ContinuousClock.now)
        return snapshot
    }
}

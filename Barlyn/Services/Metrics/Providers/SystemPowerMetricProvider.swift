import Foundation

/// Total power the Mac is drawing from the wall adapter, in watts.
///
/// Distinct from `BatteryPowerMetricProvider`: this is what the adapter delivers to the whole
/// machine, whereas battery power is only what enters or leaves the cell. On AC with a charged
/// battery the two read roughly `N W` and `0 W` respectively. Users routinely conflate them, so
/// they are shown as separate, separately-labelled metrics rather than one "power" number.
///
/// Unavailable on battery, because there is no adapter input to measure — that is reported as an
/// explicit unavailable reading, not as 0 W.
nonisolated struct SystemPowerMetricProvider: MetricProvider {
    let descriptor = MetricDescriptor(
        id: .systemPowerInput,
        displayName: "System Power Draw",
        shortName: "Power",
        symbolName: "powerplug",
        unit: .watts,
        category: .power,
        preferredInterval: .seconds(2),
        provenance: .undocumentedInterface(
            interface: "IORegistry AppleSmartBattery PowerTelemetryData.SystemPowerIn",
            caveat: "Read from an undocumented IORegistry entry; keys are not guaranteed across models."
        )
    )

    let powerSource: PowerSourceService

    init(powerSource: PowerSourceService) {
        self.powerSource = powerSource
    }

    func isSupported() async -> Bool {
        // The telemetry dictionary hangs off the battery service, so a machine without a battery
        // cannot report it here even when it obviously has an adapter.
        guard await powerSource.isBatteryPresent() else { return false }
        guard let snapshot = try? await powerSource.snapshot() else { return false }
        return snapshot.systemPowerInMilliwatts != nil
    }

    func read() async throws(MetricError) -> MetricReading {
        let snapshot = try await powerSource.snapshot()

        guard let watts = snapshot.systemInputWatts else {
            throw MetricError.implausibleValue(detail: "SystemPowerIn absent from PowerTelemetryData")
        }

        // Running on battery: the adapter reports 0 mW because there is no adapter, which is a
        // different statement from "the Mac is consuming 0 W".
        guard snapshot.isExternalConnected else {
            return .unavailable(.failed(.unsupportedOnThisHardware(detail: "not connected to power")))
        }

        var components: [MetricComponent] = []
        if let rated = snapshot.adapterRatedWatts {
            components.append(
                MetricComponent(id: "adapterRated", label: "Adapter", value: .watts(Double(rated)))
            )
        }

        return .checked(
            .watts(watts),
            components: components,
            detail: "system power in \(snapshot.systemPowerInMilliwatts ?? 0) mW"
        )
    }
}

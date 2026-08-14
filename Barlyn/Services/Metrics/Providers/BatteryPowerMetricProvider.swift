import Foundation

/// Power flowing into or out of the battery, in watts.
///
/// Sign convention: **negative while discharging, positive while charging**, matching the sign
/// of the `Amperage` key it is derived from. The UI shows the sign explicitly (`-4.8 W`,
/// `+32.4 W`) because the direction is the most important part of the number.
///
/// This is *battery-side* power — energy entering or leaving the cell. It is not the machine's
/// total consumption: on AC with a charged battery it reads ~0 W while the Mac may be drawing
/// tens of watts from the adapter. `SystemPowerMetricProvider` reports that other quantity.
nonisolated struct BatteryPowerMetricProvider: MetricProvider {
    let descriptor = MetricDescriptor(
        id: .batteryPower,
        displayName: "Battery Power",
        shortName: "Battery",
        symbolName: "minus.plus.batteryblock",
        unit: .watts,
        category: .power,
        preferredInterval: .seconds(2),
        provenance: .undocumentedInterface(
            interface: "IORegistry AppleSmartBattery (Amperage × Voltage)",
            caveat: "Read from an undocumented IORegistry entry; keys are not guaranteed across models."
        )
    )

    let powerSource: PowerSourceService

    init(powerSource: PowerSourceService) {
        self.powerSource = powerSource
    }

    func isSupported() async -> Bool {
        await powerSource.isBatteryPresent()
    }

    func read() async throws(MetricError) -> MetricReading {
        let snapshot = try await powerSource.snapshot()

        // A battery that reports no voltage is not a 0 W battery, it is a battery we failed to
        // read. Saying so beats publishing a confident zero.
        guard snapshot.voltage > 0 else {
            throw MetricError.implausibleValue(detail: "battery voltage reported as \(snapshot.voltage) mV")
        }

        var components: [MetricComponent] = [
            MetricComponent(id: "voltage", label: "Voltage", value: .init(Double(snapshot.voltage) / 1000, .volts)),
            MetricComponent(id: "amperage", label: "Current", value: .init(Double(snapshot.amperage) / 1000, .amperes)),
        ]
        if let charge = snapshot.chargePercent {
            components.append(
                MetricComponent(id: "charge", label: "Charge", value: .percent(Double(charge)))
            )
        }
        components.append(
            MetricComponent(id: "state", label: "State", value: .init(Double(snapshot.state.rawValue), .powerState))
        )

        return .checked(
            .watts(snapshot.batteryWatts),
            components: components,
            detail: "battery \(snapshot.amperage) mA × \(snapshot.voltage) mV"
        )
    }
}

nonisolated extension PowerSourceService.Snapshot {
    /// Charging state, resolved from the several booleans the registry exposes.
    var state: BatteryState {
        if !isExternalConnected { return .discharging }
        if isCharging { return .charging }
        if isFullyCharged { return .full }
        return .connectedNotCharging
    }
}

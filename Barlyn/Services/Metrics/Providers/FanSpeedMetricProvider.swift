import Foundation

/// Fan speed in RPM, read from the SMC.
///
/// Only `F<n>Ac` keys are used — those are measured tachometer values. The neighbouring
/// `F<n>Mn`, `F<n>Mx` and `F<n>Tg` keys are the controller's minimum, maximum and *target*
/// speeds; publishing a target as though it were an actual reading would be a fabricated value
/// in the most literal sense, since the fan may not have reached it.
///
/// Fanless Macs (MacBook Air, most iPads-turned-Macs) expose no such keys, so the metric is not
/// registered there rather than showing a permanent zero.
nonisolated struct FanSpeedMetricProvider: MetricProvider {
    let descriptor = MetricDescriptor(
        id: .fanSpeed,
        displayName: "Fan Speed",
        shortName: "Fan",
        symbolName: "fan.fill",
        unit: .revolutionsPerMinute,
        category: .thermal,
        preferredInterval: .seconds(5),
        provenance: .undocumentedInterface(
            interface: "AppleSMC keys F…Ac (tachometer actuals)",
            caveat: "Sensor naming is reverse-engineered, not documented by Apple, and may differ on other Macs."
        )
    )

    let smc: SMCService

    init(smc: SMCService) {
        self.smc = smc
    }

    func isSupported() async -> Bool {
        guard await smc.isAvailable() else { return false }
        return await !smc.readKeyedValues(in: .fanSpeed, unit: .revolutionsPerMinute).isEmpty
    }

    func read() async throws(MetricError) -> MetricReading {
        let fans = await smc.readKeyedValues(in: .fanSpeed, unit: .revolutionsPerMinute)
                            .sorted { $0.key < $1.key }

        guard !fans.isEmpty else {
            throw MetricError.unsupportedOnThisHardware(detail: "no fan tachometers found via SMC")
        }

        // The headline is the fastest fan rather than the mean: it is the one determining audible
        // noise, and an average across a spinning and an idle fan describes neither.
        let peak = fans.map(\.value).max() ?? 0

        let components = fans.enumerated().map { index, fan in
            MetricComponent(
                id: fan.key,
                label: fans.count == 1 ? "Fan" : "Fan \(index + 1)",
                value: .init(fan.value, .revolutionsPerMinute)
            )
        }

        return .checked(
            .init(peak, .revolutionsPerMinute),
            components: components,
            detail: "fastest of \(fans.count) fan(s)"
        )
    }
}

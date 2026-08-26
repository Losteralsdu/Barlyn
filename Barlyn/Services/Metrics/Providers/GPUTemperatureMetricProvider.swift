import Foundation

/// GPU cluster die temperature, read from the SMC.
///
/// Same interface, same caveats and same honesty rules as `CPUTemperatureMetricProvider`: the
/// `Tg…` prefix is understood to mean GPU cluster die from observation rather than Apple
/// documentation, values are range-checked, and the metric is simply not registered on a Mac
/// where no plausible sensor is found.
nonisolated struct GPUTemperatureMetricProvider: MetricProvider {
    let descriptor = MetricDescriptor(
        id: .gpuTemperature,
        displayName: "GPU Temperature",
        shortName: "GPU",
        symbolName: "thermometer.medium",
        unit: .celsius,
        category: .thermal,
        preferredInterval: .seconds(5),
        provenance: .undocumentedInterface(
            interface: "AppleSMC keys Tg… (GPU cluster)",
            caveat: "Sensor naming is reverse-engineered, not documented by Apple, and may differ on other Macs."
        )
    )

    let smc: SMCService

    init(smc: SMCService) {
        self.smc = smc
    }

    func isSupported() async -> Bool {
        guard await smc.isAvailable() else { return false }
        return await !smc.readValues(in: .gpu, unit: .celsius).isEmpty
    }

    func read() async throws(MetricError) -> MetricReading {
        let readings = await smc.readValues(in: .gpu, unit: .celsius)

        guard !readings.isEmpty else {
            throw MetricError.unsupportedOnThisHardware(detail: "no plausible GPU die sensors found via SMC")
        }

        let mean = readings.reduce(0, +) / Double(readings.count)
        let peak = readings.max() ?? mean

        return .checked(
            .celsius(mean),
            components: [
                MetricComponent(id: "peak", label: "Hottest", value: .celsius(peak)),
                MetricComponent(id: "sensors", label: "Sensors", value: .init(Double(readings.count), .count)),
            ],
            detail: "mean of \(readings.count) GPU die sensors"
        )
    }
}

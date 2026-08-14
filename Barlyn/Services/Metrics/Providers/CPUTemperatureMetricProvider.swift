import Foundation

/// CPU die temperature, read from the SMC.
///
/// **What this number is.** The mean of every plausible reading from the performance-core cluster
/// die sensors discovered on this machine (24 of them on the development Mac, keys `Tp00`–`Tp1g`).
/// The peak sensor and the sensor count travel alongside as components, because on a
/// many-sensor die the spread between mean and hottest core is real information, and a single
/// averaged figure quietly discards it.
///
/// **What it is not.** It is not an Apple-documented "CPU temperature" reading; no such public
/// API exists. The `Tp` prefix is understood to mean performance-core die from community
/// reverse engineering and observation, not from Apple. The descriptor therefore declares
/// `.undocumentedInterface`, and every surface that renders this metric shows the caveat.
///
/// If no plausible sensor is found — a different chip generation, a naming change, an
/// unsandboxed-process requirement not met — the metric reports unavailable and the app falls
/// back to `ThermalPressureMetricProvider`, which is fully supported. It never guesses.
nonisolated struct CPUTemperatureMetricProvider: MetricProvider {
    let descriptor = MetricDescriptor(
        id: .cpuTemperature,
        displayName: "CPU Temperature",
        shortName: "Temp",
        symbolName: "thermometer.medium",
        unit: .celsius,
        category: .thermal,
        // Die temperature moves slowly and each sample costs one IOKit round trip per sensor,
        // so this is sampled far less often than CPU usage.
        preferredInterval: .seconds(5),
        provenance: .undocumentedInterface(
            interface: "AppleSMC keys Tp… (performance-core cluster)",
            caveat: "Sensor naming is reverse-engineered, not documented by Apple, and may differ on other Macs."
        )
    )

    let smc: SMCService

    init(smc: SMCService) {
        self.smc = smc
    }

    func isSupported() async -> Bool {
        guard await smc.isAvailable() else { return false }
        return await !Self.temperatures(from: smc).isEmpty
    }

    func read() async throws(MetricError) -> MetricReading {
        let readings = await Self.temperatures(from: smc)

        guard !readings.isEmpty else {
            throw MetricError.unsupportedOnThisHardware(
                detail: "no plausible CPU die sensors found via SMC"
            )
        }

        let mean = readings.reduce(0, +) / Double(readings.count)
        let peak = readings.max() ?? mean

        return .checked(
            .celsius(mean),
            components: [
                MetricComponent(id: "peak", label: "Hottest", value: .celsius(peak)),
                MetricComponent(id: "sensors", label: "Sensors", value: .init(Double(readings.count), .count)),
            ],
            detail: "mean of \(readings.count) die sensors"
        )
    }

    /// Prefers performance cores, falling back to efficiency cores and then Intel keys, so the
    /// metric works across chip families without a hard-coded per-model table.
    private static func temperatures(from smc: SMCService) async -> [Double] {
        for family in [SMCService.SensorFamily.cpuPerformanceCore, .cpuEfficiencyCore, .cpuIntel] {
            let readings = await smc.readTemperatures(in: family)
            if !readings.isEmpty { return readings }
        }
        return []
    }
}

import Foundation

/// macOS thermal pressure, from the public `ProcessInfo.thermalState` API.
///
/// The guaranteed baseline for thermal information. Unlike SMC die temperature this is
/// documented, supported, sandbox-safe and works on every Mac, so it is what the app can always
/// promise. It answers "is this Mac thermally constrained right now" rather than "how many
/// degrees", which is often the question the user actually has.
///
/// Kept as a separate metric rather than a fallback value inside the temperature provider: they
/// measure different things, and silently substituting one for the other would be precisely the
/// mislabelling the temperature provider goes to such lengths to avoid.
nonisolated struct ThermalPressureMetricProvider: MetricProvider {
    let descriptor = MetricDescriptor(
        id: .thermalPressure,
        displayName: "Thermal Pressure",
        shortName: "Thermal",
        symbolName: "fan",
        unit: .thermalLevel,
        category: .thermal,
        // The OS coalesces this into a notification-driven state; polling faster buys nothing.
        preferredInterval: .seconds(10),
        provenance: .publicAPI(api: "ProcessInfo.thermalState")
    )

    func read() async throws(MetricError) -> MetricReading {
        let level = ThermalPressureLevel(ProcessInfo.processInfo.thermalState)
        return .checked(
            .init(Double(level.rawValue), .thermalLevel),
            detail: "thermal state \(level.displayName)"
        )
    }
}

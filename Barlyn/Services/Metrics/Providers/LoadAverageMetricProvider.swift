import Foundation

/// Kernel load average over 1, 5 and 15 minutes.
///
/// Included in Phase 1 as the second reference provider: it exercises the composite-reading path
/// (`MetricSnapshot.components`) that CPU and memory will rely on in Phase 3, using an API that
/// is trivially correct and needs no permissions.
///
/// Load average is a count of runnable threads, not a percentage — it is intentionally *not*
/// normalised by core count here, because doing so would present a derived number as if it were
/// the value the kernel reports.
nonisolated struct LoadAverageMetricProvider: MetricProvider {
    let descriptor = MetricDescriptor(
        id: MetricIdentifier("system.loadAverage"),
        displayName: "Load Average",
        shortName: "Load",
        symbolName: "gauge.with.dots.needle.33percent",
        unit: .count,
        category: .processor,
        // The kernel itself only recomputes these every 5 seconds.
        preferredInterval: .seconds(5),
        provenance: .publicAPI(api: "getloadavg(3)")
    )

    func read() async throws(MetricError) -> MetricReading {
        var samples = [Double](repeating: 0, count: 3)
        let returned = getloadavg(&samples, 3)

        guard returned == 3 else {
            throw MetricError.systemCallFailed(api: "getloadavg", code: Int32(returned))
        }

        return .available(
            MetricSnapshot(
                value: .init(samples[0], .count),
                components: [
                    MetricComponent(id: "1m", label: "1 min", value: .init(samples[0], .count)),
                    MetricComponent(id: "5m", label: "5 min", value: .init(samples[1], .count)),
                    MetricComponent(id: "15m", label: "15 min", value: .init(samples[2], .count)),
                ]
            )
        )
    }
}

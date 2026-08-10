import Foundation

/// Wall-clock time since the machine last booted.
///
/// Uses `sysctl(KERN_BOOTTIME)` rather than `ProcessInfo.systemUptime`. The two disagree, and
/// the difference matters on laptops: `systemUptime` is derived from `mach_absolute_time`, which
/// does not advance while the system is asleep, so it reports "awake time" and can be many hours
/// behind what `uptime(1)` and Activity Monitor show. `KERN_BOOTTIME` is a wall-clock boot
/// timestamp and matches the number users expect to see.
nonisolated struct UptimeMetricProvider: MetricProvider {
    let descriptor = MetricDescriptor(
        id: .uptime,
        displayName: "Uptime",
        shortName: "Uptime",
        symbolName: "clock.arrow.circlepath",
        unit: .seconds,
        category: .system,
        // Uptime advances predictably; there is nothing to gain from sampling it quickly.
        preferredInterval: .seconds(30),
        provenance: .publicAPI(api: "sysctl KERN_BOOTTIME")
    )

    func read() async throws(MetricError) -> MetricReading {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]

        let status = sysctl(&mib, UInt32(mib.count), &bootTime, &size, nil, 0)
        guard status == 0 else {
            throw MetricError.systemCallFailed(api: "sysctl(KERN_BOOTTIME)", code: errno)
        }

        let bootDate = Date(timeIntervalSince1970: Double(bootTime.tv_sec))
        let uptime = Date.now.timeIntervalSince(bootDate)

        guard uptime >= 0 else {
            throw MetricError.implausibleValue(detail: "negative uptime \(uptime)s")
        }

        return .available(MetricSnapshot(value: .seconds(uptime)))
    }
}

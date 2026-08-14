import Foundation

/// Physical memory usage.
///
/// **Definition of "used", and why it needs one.** macOS publishes no single "used memory"
/// number. `host_statistics64` returns a page census, and every headline figure is a *choice*
/// about which categories to count — different tools make different choices and disagree loudly.
/// Measured together on the development Mac (24 GiB):
///
/// | Definition | Result |
/// |---|---|
/// | App Memory + wired + compressed | 12.6 GiB |
/// | active + wired + compressed | 12.7 GiB |
/// | total − free − speculative (what `top` reports as "used") | 20.2 GiB |
///
/// Barlyn reports the first, mirroring how Activity Monitor composes its "Memory Used" figure:
///
///     appMemory = internal_page_count − purgeable_count
///     used      = appMemory + wire_count + compressor_page_count
///
/// `internal` (anonymous) rather than `active` is the right base because inactive *anonymous*
/// pages are still application memory; `purgeable` is subtracted because the system can reclaim
/// it without cost. File-backed pages (`external`) are excluded — they are cache, not usage.
///
/// **Not independently verified against Activity Monitor's UI.** The composition follows Apple's
/// description of that figure, and it is self-consistent, but nobody has put the two side by side
/// on this machine. Confirming it is an open task. The full census ships as components so the
/// choice is inspectable rather than buried.
nonisolated struct MemoryMetricProvider: MetricProvider {
    let descriptor = MetricDescriptor(
        id: .memoryUsage,
        displayName: "Memory Usage",
        shortName: "RAM",
        symbolName: "memorychip",
        unit: .percent,
        category: .memory,
        preferredInterval: .seconds(2),
        provenance: .derived(
            from: "host_statistics64(HOST_VM_INFO64): (internal − purgeable) + wired + compressed"
        )
    )

    func read() async throws(MetricError) -> MetricReading {
        var statistics = vm_statistics64()
        var count = UInt32(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let status = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard status == KERN_SUCCESS else {
            throw MetricError.systemCallFailed(api: "host_statistics64", code: status)
        }

        // Page size is 16384 on Apple Silicon, not the 4096 that older sample code assumes;
        // hard-coding it would make every figure four times wrong. `host_page_size` is used
        // rather than the `vm_kernel_page_size` global because the latter is mutable shared
        // state and not concurrency-safe under Swift 6.
        var pageSizeValue: vm_size_t = 0
        let pageStatus = host_page_size(mach_host_self(), &pageSizeValue)
        guard pageStatus == KERN_SUCCESS, pageSizeValue > 0 else {
            throw MetricError.systemCallFailed(api: "host_page_size", code: pageStatus)
        }
        let pageSize = UInt64(pageSizeValue)
        let total = ProcessInfo.processInfo.physicalMemory

        let active = UInt64(statistics.active_count) * pageSize
        let inactive = UInt64(statistics.inactive_count) * pageSize
        let wired = UInt64(statistics.wire_count) * pageSize
        let compressed = UInt64(statistics.compressor_page_count) * pageSize
        let free = UInt64(statistics.free_count) * pageSize
        let speculative = UInt64(statistics.speculative_count) * pageSize
        let purgeable = UInt64(statistics.purgeable_count) * pageSize
        let anonymous = UInt64(statistics.internal_page_count) * pageSize
        let fileBacked = UInt64(statistics.external_page_count) * pageSize

        // Saturating subtraction: these counters are sampled independently and can momentarily
        // disagree, and an unsigned underflow here would produce a 16-exabyte "app memory".
        let appMemory = anonymous > purgeable ? anonymous - purgeable : 0
        let used = appMemory + wired + compressed

        guard total > 0 else {
            throw MetricError.implausibleValue(detail: "physicalMemory reported 0")
        }
        let percent = Double(used) / Double(total) * 100

        return .checked(
            .percent(percent),
            components: [
                MetricComponent(id: "used", label: "Used", value: .bytes(used)),
                MetricComponent(id: "total", label: "Total", value: .bytes(total)),
                MetricComponent(id: "app", label: "App Memory", value: .bytes(appMemory)),
                MetricComponent(id: "wired", label: "Wired", value: .bytes(wired)),
                MetricComponent(id: "compressed", label: "Compressed", value: .bytes(compressed)),
                MetricComponent(id: "cached", label: "Cached Files", value: .bytes(fileBacked)),
                MetricComponent(id: "free", label: "Free", value: .bytes(free)),
                MetricComponent(id: "active", label: "Active", value: .bytes(active)),
                MetricComponent(id: "inactive", label: "Inactive", value: .bytes(inactive)),
                MetricComponent(id: "speculative", label: "Speculative", value: .bytes(speculative)),
                MetricComponent(id: "purgeable", label: "Purgeable", value: .bytes(purgeable)),
            ],
            detail: "memory \(percent)% of \(total) bytes"
        )
    }
}

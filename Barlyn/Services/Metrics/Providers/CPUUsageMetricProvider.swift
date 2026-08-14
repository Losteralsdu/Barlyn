import Foundation

/// Processor utilisation across all cores.
///
/// `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` returns *cumulative tick counters* since boot,
/// not instantaneous usage. A single sample therefore says nothing about current load — usage
/// only exists as a difference between two samples. That is why this provider is an `actor`:
/// it has to retain the previous counters.
///
/// The first `read()` deliberately reports "not yet sampled" rather than usage-since-boot.
/// Usage-since-boot is a real number, but it is not what a live CPU readout claims to be, and
/// presenting it as current load would be exactly the kind of quiet mislabelling this app avoids.
actor CPUUsageMetricProvider: MetricProvider {
    nonisolated let descriptor = MetricDescriptor(
        id: .cpuUsage,
        displayName: "Processor Usage",
        shortName: "CPU",
        symbolName: "cpu",
        unit: .percent,
        category: .processor,
        preferredInterval: .seconds(1),
        provenance: .publicAPI(api: "host_processor_info(PROCESSOR_CPU_LOAD_INFO)")
    )

    private struct Ticks {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        var total: UInt64 { user + system + idle + nice }
    }

    private var previous: Ticks?

    func read() async throws(MetricError) -> MetricReading {
        let current = try Self.currentTicks()

        guard let previous else {
            self.previous = current
            return .unavailable(.notYetSampled)
        }

        let deltaTotal = current.total &- previous.total
        // Two samples inside the same tick produce no elapsed time to divide by. Keeping the
        // prior reading pending is more honest than dividing by zero into a fabricated 0%.
        guard deltaTotal > 0 else { return .unavailable(.notYetSampled) }

        self.previous = current

        let divisor = Double(deltaTotal)
        let user = Double(current.user &- previous.user) / divisor * 100
        let system = Double(current.system &- previous.system) / divisor * 100
        let idle = Double(current.idle &- previous.idle) / divisor * 100
        let nice = Double(current.nice &- previous.nice) / divisor * 100

        // Derived from idle rather than summing the busy states: the two agree, and subtracting
        // idle avoids accumulating rounding error across four terms.
        let usage = (100 - idle).clamped(to: 0...100)

        return .checked(
            .percent(usage),
            components: [
                MetricComponent(id: "user", label: "User", value: .percent(user.clamped(to: 0...100))),
                MetricComponent(id: "system", label: "System", value: .percent(system.clamped(to: 0...100))),
                MetricComponent(id: "idle", label: "Idle", value: .percent(idle.clamped(to: 0...100))),
                MetricComponent(id: "nice", label: "Nice", value: .percent(nice.clamped(to: 0...100))),
            ],
            detail: "cpu usage \(usage)%"
        )
    }

    /// Sums per-core counters into a single machine-wide figure.
    private static func currentTicks() throws(MetricError) -> Ticks {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let status = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount)
        guard status == KERN_SUCCESS, let info else {
            throw MetricError.systemCallFailed(api: "host_processor_info", code: status)
        }

        // The kernel allocates this buffer on our behalf; failing to release it leaks on every
        // sample, which for a continuously-running app means leaking forever.
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        var ticks = Ticks()
        info.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { pointer in
            for core in 0..<Int(coreCount) {
                let base = core * Int(CPU_STATE_MAX)
                ticks.user &+= UInt64(pointer[base + Int(CPU_STATE_USER)])
                ticks.system &+= UInt64(pointer[base + Int(CPU_STATE_SYSTEM)])
                ticks.idle &+= UInt64(pointer[base + Int(CPU_STATE_IDLE)])
                ticks.nice &+= UInt64(pointer[base + Int(CPU_STATE_NICE)])
            }
        }
        return ticks
    }
}

nonisolated extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

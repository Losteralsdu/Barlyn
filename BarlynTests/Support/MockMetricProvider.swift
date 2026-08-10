import Foundation
import Synchronization
@testable import Barlyn

/// Metric provider with scriptable behaviour, so registry and sampler logic can be tested
/// without touching real hardware.
final class MockMetricProvider: MetricProvider {
    let descriptor: MetricDescriptor

    private let outcome: Outcome
    private let supported: Bool
    private let readCount = Mutex<Int>(0)

    enum Outcome: Sendable {
        case value(Double)
        case failure(MetricError)
        case unavailable(MetricUnavailability)
    }

    init(
        id: MetricIdentifier,
        unit: MetricUnit = .percent,
        interval: Duration = AppConfiguration.minimumSampleInterval,
        supported: Bool = true,
        outcome: Outcome = .value(42)
    ) {
        self.descriptor = MetricDescriptor(
            id: id,
            displayName: "Mock \(id.rawValue)",
            shortName: "Mock",
            symbolName: "questionmark",
            unit: unit,
            category: .system,
            preferredInterval: interval,
            provenance: .publicAPI(api: "mock")
        )
        self.supported = supported
        self.outcome = outcome
    }

    var timesRead: Int { readCount.withLock { $0 } }

    func isSupported() async -> Bool { supported }

    func read() async throws(MetricError) -> MetricReading {
        readCount.withLock { $0 += 1 }
        switch outcome {
        case .value(let magnitude):
            return .available(MetricSnapshot(value: MetricValue(magnitude, descriptor.unit)))
        case .failure(let error):
            throw error
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }
}

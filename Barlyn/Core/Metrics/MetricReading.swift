import Foundation

/// Why a metric has no value right now.
///
/// "Unavailable" is a first-class, typed state rather than a `nil` or a zero. This is the
/// mechanism that keeps Barlyn honest: a provider that cannot measure something must say so,
/// and the UI must render that as "—" with a reason instead of a plausible-looking number.
nonisolated enum MetricUnavailability: Sendable, Hashable, Codable {
    /// Registered, but no sample has completed yet. Normal for the first moments after launch.
    case notYetSampled
    /// The user switched this metric off.
    case disabledByUser
    /// Sampling failed or the hardware does not expose it.
    case failed(MetricError)

    var userMessage: String? {
        switch self {
        case .notYetSampled, .disabledByUser: nil
        case .failed(let error): error.userMessage
        }
    }

    var isActionable: Bool {
        if case .failed(let error) = self { return error.isActionable }
        return false
    }
}

/// A successful measurement.
nonisolated struct MetricSnapshot: Sendable, Hashable, Codable {
    /// The headline number shown in compact UI.
    let value: MetricValue
    /// Optional breakdown (user/system/idle, used/total/wired). Empty for scalar metrics.
    let components: [MetricComponent]
    let timestamp: Date

    init(value: MetricValue, components: [MetricComponent] = [], timestamp: Date = .now) {
        self.value = value
        self.components = components
        self.timestamp = timestamp
    }

    func component(_ id: String) -> MetricComponent? {
        components.first { $0.id == id }
    }
}

/// The result of sampling a metric: either a real measurement or a stated reason for its absence.
nonisolated enum MetricReading: Sendable, Hashable, Codable {
    case available(MetricSnapshot)
    case unavailable(MetricUnavailability)

    static let notYetSampled = MetricReading.unavailable(.notYetSampled)

    var snapshot: MetricSnapshot? {
        if case .available(let snapshot) = self { return snapshot }
        return nil
    }

    var value: MetricValue? { snapshot?.value }

    var isAvailable: Bool { snapshot != nil }

    /// Builds an `available` reading, downgrading to `unavailable` when the value fails the
    /// plausibility check for its unit. Providers reading undocumented sensors should route
    /// through this rather than constructing `.available` directly.
    static func checked(
        _ value: MetricValue,
        components: [MetricComponent] = [],
        timestamp: Date = .now,
        detail: @autoclosure () -> String
    ) -> MetricReading {
        guard value.isPlausible else {
            return .unavailable(.failed(.implausibleValue(detail: detail())))
        }
        return .available(MetricSnapshot(value: value, components: components, timestamp: timestamp))
    }
}

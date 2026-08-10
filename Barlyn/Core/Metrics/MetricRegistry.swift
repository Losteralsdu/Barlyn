import Foundation
import OSLog

/// The catalogue of metrics available in this process.
///
/// Registration happens once at the composition root. Every consumer (menu bar, dashboard,
/// Quick Launcher, Settings) reads descriptors from here, which is what makes "add a provider,
/// it shows up everywhere" true rather than aspirational.
///
/// Main-actor isolated because it is read directly by SwiftUI and mutated only during launch.
@MainActor
@Observable
final class MetricRegistry {
    private var providersByID: [MetricIdentifier: any MetricProvider] = [:]

    /// Descriptors in registration order. Stable ordering matters: it is the default order of
    /// menu bar items and dashboard cards before the user reorders them.
    private(set) var descriptors: [MetricDescriptor] = []

    init() {}

    /// Registers a provider whose support has already been established.
    ///
    /// Duplicate identifiers are rejected rather than silently replacing an existing provider —
    /// a duplicate is a programming error, and overwriting would make which provider wins depend
    /// on registration order.
    @discardableResult
    func register(_ provider: any MetricProvider) -> Bool {
        let id = provider.descriptor.id
        guard providersByID[id] == nil else {
            AppLog.metrics.error("Duplicate metric registration ignored for '\(id.rawValue, privacy: .public)'")
            return false
        }
        providersByID[id] = provider
        descriptors.append(provider.descriptor)
        AppLog.metrics.debug("Registered metric '\(id.rawValue, privacy: .public)'")
        return true
    }

    /// Registers a provider only if it reports support on this machine.
    ///
    /// Unsupported metrics are omitted entirely rather than displayed in a permanent error
    /// state — a fanless Mac should not show an empty "Fan Speed" row forever.
    @discardableResult
    func registerIfSupported(_ provider: any MetricProvider) async -> Bool {
        guard await provider.isSupported() else {
            AppLog.metrics.notice(
                "Metric '\(provider.descriptor.id.rawValue, privacy: .public)' unsupported on this Mac; not registered"
            )
            return false
        }
        return register(provider)
    }

    func provider(for id: MetricIdentifier) -> (any MetricProvider)? { providersByID[id] }

    func descriptor(for id: MetricIdentifier) -> MetricDescriptor? {
        descriptors.first { $0.id == id }
    }

    func descriptors(in category: MetricCategory) -> [MetricDescriptor] {
        descriptors.filter { $0.category == category }
    }

    var isEmpty: Bool { providersByID.isEmpty }
    var count: Int { providersByID.count }
}

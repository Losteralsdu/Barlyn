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

    /// Registration order, which is an implementation detail — see `descriptors`.
    private var registered: [MetricDescriptor] = []

    /// Descriptors in default display order: grouped by category, and stable (registration
    /// order) within a category.
    ///
    /// Sorting by category rather than arrival keeps the layout deterministic even though
    /// hardware-probed providers register in a later wave (ADR-008). Swift's `sorted(by:)` is
    /// not a stable sort, so registration index is folded into the comparison explicitly.
    var descriptors: [MetricDescriptor] {
        registered.enumerated()
            .sorted { left, right in
                let leftKey = (left.element.category.sortIndex, left.offset)
                let rightKey = (right.element.category.sortIndex, right.offset)
                return leftKey < rightKey
            }
            .map(\.element)
    }

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
        registered.append(provider.descriptor)
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

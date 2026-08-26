import Foundation

/// Decides which metric cards the dashboard shows and in what order.
///
/// Mirrors `MenuBarConfiguration`, with one deliberate difference: the menu bar stores a
/// *show-list* because its space is scarce and its contents must be a chosen few, while the
/// dashboard stores a *hide-list* so that a newly added provider appears without the user having
/// to find and enable it.
@MainActor
@Observable
final class DashboardConfiguration {
    private let preferences: PreferenceStore
    private let registry: MetricRegistry

    init(preferences: PreferenceStore, registry: MetricRegistry) {
        self.preferences = preferences
        self.registry = registry
    }

    /// Cards to display: everything registered, minus hidden, in the user's order.
    var visibleMetrics: [MetricDescriptor] {
        let hidden = Set(preferences[PreferenceKeys.dashboardHiddenMetrics])
        let candidates = registry.descriptors.filter { !hidden.contains($0.id) }

        let order = preferences[PreferenceKeys.dashboardOrder]
        guard !order.isEmpty else { return candidates }

        // Ordered metrics first, in the user's sequence; anything the order list has never seen
        // (a metric added by a later version) keeps its default category position at the end,
        // rather than being dropped or silently sorted to the front.
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        let ordered = candidates.filter { position[$0.id] != nil }
            .sorted { (position[$0.id] ?? 0) < (position[$1.id] ?? 0) }
        let unordered = candidates.filter { position[$0.id] == nil }
        return ordered + unordered
    }

    var hiddenMetrics: [MetricDescriptor] {
        let hidden = Set(preferences[PreferenceKeys.dashboardHiddenMetrics])
        return registry.descriptors.filter { hidden.contains($0.id) }
    }

    var showsCharts: Bool { preferences[PreferenceKeys.dashboardShowsCharts] }

    func isVisible(_ id: MetricIdentifier) -> Bool {
        !preferences[PreferenceKeys.dashboardHiddenMetrics].contains(id)
    }

    func setVisible(_ visible: Bool, for id: MetricIdentifier) {
        var hidden = preferences[PreferenceKeys.dashboardHiddenMetrics]
        if visible {
            hidden.removeAll { $0 == id }
        } else if !hidden.contains(id) {
            hidden.append(id)
        }
        preferences[PreferenceKeys.dashboardHiddenMetrics] = hidden
    }

    /// Moves a card one position earlier or later.
    ///
    /// The stored order is materialised from the current visible order on first move, so a user
    /// who has never reordered anything does not carry a stale list that would freeze out
    /// metrics added later.
    func move(_ id: MetricIdentifier, by offset: Int) {
        var order = preferences[PreferenceKeys.dashboardOrder]
        if order.isEmpty {
            order = visibleMetrics.map(\.id)
        }
        guard let index = order.firstIndex(of: id) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        preferences[PreferenceKeys.dashboardOrder] = order
    }

    func setShowsCharts(_ shows: Bool) {
        preferences[PreferenceKeys.dashboardShowsCharts] = shows
    }

    /// Forgets any custom order and un-hides everything.
    func resetLayout() {
        preferences.reset(PreferenceKeys.dashboardOrder)
        preferences.reset(PreferenceKeys.dashboardHiddenMetrics)
    }
}

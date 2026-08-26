import Foundation
import OSLog

/// Turns the user's menu bar preferences into sampler demand.
///
/// The menu bar label is visible for the app's entire lifetime, so unlike every other consumer
/// its demand is never released while the app runs. That makes it the one place where the
/// sampling cadence is a real, continuous energy cost — hence a user-facing interval setting,
/// and hence this being the single point that applies it.
///
/// Kept out of the views: a SwiftUI `MenuBarExtra` label is not a reliable place to run
/// lifecycle work, and this has to happen whether or not the panel has ever been opened.
@MainActor
@Observable
final class MenuBarConfiguration {
    private let preferences: PreferenceStore
    private let registry: MetricRegistry
    private let sampler: MetricSampler

    init(preferences: PreferenceStore, registry: MetricRegistry, sampler: MetricSampler) {
        self.preferences = preferences
        self.registry = registry
        self.sampler = sampler
    }

    /// Metrics the user has chosen, filtered to those actually registered on this Mac and kept
    /// in the user's order.
    ///
    /// Filtering matters: a preference can name a metric whose hardware is absent (a fan on a
    /// fanless Mac) or that was removed in a later version. Those are skipped rather than shown
    /// as permanently broken rows.
    var visibleMetrics: [MetricDescriptor] {
        preferences[PreferenceKeys.menuBarMetrics].compactMap { registry.descriptor(for: $0) }
    }

    var style: MenuBarStyle { preferences[PreferenceKeys.menuBarStyle] }

    /// Applies the current preferences to the sampler. Idempotent; safe to call after any edit.
    func apply() {
        let metrics = visibleMetrics
        let interval = Duration.seconds(preferences[PreferenceKeys.menuBarUpdateInterval])

        for descriptor in metrics {
            sampler.setIntervalOverride(interval, for: descriptor.id)
        }
        sampler.setDemand(Set(metrics.map(\.id)), for: .menuBar)

        AppLog.metrics.notice(
            "Menu bar showing \(metrics.count) metrics every \(interval.milliseconds) ms"
        )
    }

    // MARK: - Editing (backs Settings)

    func isVisible(_ id: MetricIdentifier) -> Bool {
        preferences[PreferenceKeys.menuBarMetrics].contains(id)
    }

    func setVisible(_ visible: Bool, for id: MetricIdentifier) {
        var metrics = preferences[PreferenceKeys.menuBarMetrics]
        if visible {
            guard !metrics.contains(id) else { return }
            metrics.append(id)
        } else {
            metrics.removeAll { $0 == id }
            // Stop paying for a metric nothing displays any more.
            sampler.setIntervalOverride(nil, for: id)
        }
        preferences[PreferenceKeys.menuBarMetrics] = metrics
        apply()
    }

    /// Moves a metric one position earlier or later in the menu bar.
    ///
    /// Explicit move commands rather than drag-only reordering, so the ordering is reachable by
    /// keyboard and VoiceOver.
    func move(_ id: MetricIdentifier, by offset: Int) {
        var metrics = preferences[PreferenceKeys.menuBarMetrics]
        guard let index = metrics.firstIndex(of: id) else { return }
        let target = index + offset
        guard metrics.indices.contains(target) else { return }
        metrics.swapAt(index, target)
        preferences[PreferenceKeys.menuBarMetrics] = metrics
        apply()
    }

    func setUpdateInterval(_ seconds: Double) {
        preferences[PreferenceKeys.menuBarUpdateInterval] = seconds
        apply()
    }

    func setStyle(_ style: MenuBarStyle) {
        preferences[PreferenceKeys.menuBarStyle] = style
    }
}

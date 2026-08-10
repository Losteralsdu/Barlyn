import Foundation
import OSLog

/// Drives periodic sampling of the metrics that are actually being displayed.
///
/// Sampling is demand-driven rather than always-on. Each consumer (menu bar, dashboard, Quick
/// Launcher) declares which metrics it currently needs; the sampler polls the union and stops
/// entirely when nothing is on screen. That is the difference between an app that costs battery
/// only while visible and one that polls IOKit forever in the background.
///
/// Main-actor isolated so SwiftUI can observe `readings` directly. The actual `read()` calls are
/// `nonisolated async` and run off the main actor.
@MainActor
@Observable
final class MetricSampler {
    /// Identifies a consumer so its demand can be replaced wholesale when its UI changes.
    nonisolated struct ConsumerID: Hashable, Sendable {
        let rawValue: String
        init(_ rawValue: String) { self.rawValue = rawValue }

        static let menuBar = ConsumerID("menuBar")
        static let dashboard = ConsumerID("dashboard")
        static let quickLauncher = ConsumerID("quickLauncher")
        static let diagnostics = ConsumerID("diagnostics")
    }

    private let registry: MetricRegistry

    /// Latest reading per metric. Only contains currently-sampled metrics.
    private(set) var readings: [MetricIdentifier: MetricReading] = [:]

    private var demand: [ConsumerID: Set<MetricIdentifier>] = [:]
    private var samplingTasks: [MetricIdentifier: Task<Void, Never>] = [:]

    /// Last error logged per metric, so a persistently failing sensor logs once instead of
    /// every interval for days.
    private var lastLoggedError: [MetricIdentifier: MetricError] = [:]

    init(registry: MetricRegistry) {
        self.registry = registry
    }

    // No `deinit` cleanup: `deinit` is nonisolated and cannot touch main-actor state. It is not
    // needed either — each sampling task holds only a weak reference to the sampler, so once the
    // sampler is released every task exits at its next iteration. Use `stopAll()` for immediate,
    // deterministic teardown.

    /// Cancels all sampling immediately, without changing recorded demand.
    func stopAll() {
        for (id, task) in samplingTasks {
            task.cancel()
            readings.removeValue(forKey: id)
        }
        samplingTasks.removeAll()
    }

    /// Metrics currently being polled.
    var activeMetrics: Set<MetricIdentifier> {
        demand.values.reduce(into: Set<MetricIdentifier>()) { $0.formUnion($1) }
    }

    /// Replaces `consumer`'s set of required metrics and reconciles the running tasks.
    func setDemand(_ metrics: Set<MetricIdentifier>, for consumer: ConsumerID) {
        if metrics.isEmpty {
            demand.removeValue(forKey: consumer)
        } else {
            demand[consumer] = metrics
        }
        reconcile()
    }

    func clearDemand(for consumer: ConsumerID) {
        setDemand([], for: consumer)
    }

    /// Reading for a metric, or `.notYetSampled` if nothing has arrived yet.
    func reading(for id: MetricIdentifier) -> MetricReading {
        readings[id] ?? .notYetSampled
    }

    // MARK: - Reconciliation

    private func reconcile() {
        let wanted = activeMetrics
        let running = Set(samplingTasks.keys)

        for id in running.subtracting(wanted) {
            samplingTasks.removeValue(forKey: id)?.cancel()
            // Drop the value too: a stale number outliving its sampler is exactly the kind of
            // silently-wrong display this architecture is meant to prevent.
            readings.removeValue(forKey: id)
            lastLoggedError.removeValue(forKey: id)
        }

        for id in wanted.subtracting(running) {
            guard let provider = registry.provider(for: id) else {
                AppLog.metrics.error("No provider registered for requested metric '\(id.rawValue, privacy: .public)'")
                continue
            }
            readings[id] = .notYetSampled
            samplingTasks[id] = makeSamplingTask(for: provider)
        }
    }

    private func makeSamplingTask(for provider: any MetricProvider) -> Task<Void, Never> {
        let id = provider.descriptor.id
        let interval = provider.descriptor.effectiveInterval

        return Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let reading = try await provider.read()
                    guard let self, !Task.isCancelled else { return }
                    self.readings[id] = reading
                    self.lastLoggedError.removeValue(forKey: id)
                } catch let error as MetricError {
                    guard let self, !Task.isCancelled else { return }
                    self.readings[id] = .unavailable(.failed(error))
                    self.logIfNew(error, for: id)
                } catch {
                    // `read()` is declared `throws(MetricError)`, but calling it through the
                    // `any MetricProvider` existential erases the typed throw back to `any Error`.
                    // This branch is therefore unreachable; it is logged rather than ignored so a
                    // future provider that breaks the contract is visible instead of silent.
                    guard let self, !Task.isCancelled else { return }
                    AppLog.metrics.fault(
                        "Provider '\(id.rawValue, privacy: .public)' threw a non-MetricError: \(String(describing: error), privacy: .public)"
                    )
                    self.readings[id] = .unavailable(.failed(.systemCallFailed(api: "read()", code: -1)))
                }

                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return // cancelled
                }
            }
        }
    }

    private func logIfNew(_ error: MetricError, for id: MetricIdentifier) {
        guard lastLoggedError[id] != error else { return }
        lastLoggedError[id] = error
        AppLog.metrics.error(
            "Metric '\(id.rawValue, privacy: .public)' failed: \(error.diagnosticDescription, privacy: .public)"
        )
    }
}

import Foundation

/// Live system metrics as launcher rows.
///
/// The launcher doubles as a system readout: opening it and typing nothing shows the current
/// state of the machine. Rows are informational — their action is `.none` — because a metric is
/// something to read, not something to run.
///
/// Main-actor isolated because the registry and sampler are. It reads whatever the sampler
/// already has; it never triggers a sample of its own, so opening the launcher costs nothing
/// beyond the demand the launcher itself declares.
@MainActor
final class MetricActionProvider: LauncherActionProvider {
    nonisolated let identifier = "metrics"

    private let registry: MetricRegistry
    private let sampler: MetricSampler
    private let formatter: MetricFormatter

    init(registry: MetricRegistry, sampler: MetricSampler, formatter: MetricFormatter) {
        self.registry = registry
        self.sampler = sampler
        self.formatter = formatter
    }

    /// `nonisolated` to satisfy the provider protocol, with an explicit hop to read the
    /// main-actor-isolated registry and sampler. Making the protocol itself `@MainActor` would
    /// instead force `ApplicationActionProvider`'s directory scan onto the main thread.
    nonisolated func results(for query: LauncherQuery) async -> [LauncherResult] {
        await MainActor.run { buildResults(for: query) }
    }

    private func buildResults(for query: LauncherQuery) -> [LauncherResult] {
        registry.descriptors.compactMap { descriptor in
            let candidates = [descriptor.displayName, descriptor.shortName, descriptor.category.displayName]
            guard let relevance = candidates
                .compactMap({ FuzzyMatcher.score(query: query.normalized, candidate: $0) })
                .max()
            else { return nil }

            let reading = sampler.reading(for: descriptor.id)
            return LauncherResult(
                id: "metric.\(descriptor.id.rawValue)",
                title: descriptor.displayName,
                subtitle: formatter.string(for: reading, style: .detailed),
                kind: .metric,
                symbolName: descriptor.symbolName,
                relevance: relevance,
                action: .none
            )
        }
    }
}

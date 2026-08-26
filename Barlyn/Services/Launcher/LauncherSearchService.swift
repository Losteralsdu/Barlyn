import Foundation

/// Runs a query across every action provider and ranks the combined results.
///
/// Providers are queried concurrently, so one slow source cannot stall the list. Adding a source
/// — clipboard in Phase 6, window actions in Phase 7 — means appending a provider here and
/// nothing else.
@MainActor
@Observable
final class LauncherSearchService {
    /// Cap on rows shown. A launcher is for the top few answers; scrolling past fifty results is
    /// a sign the query needs refining, not a longer list.
    nonisolated static let resultLimit = 40

    private var providers: [any LauncherActionProvider] = []

    private(set) var results: [LauncherResult] = []
    private(set) var isSearching = false

    /// Cancels an in-flight search when a newer keystroke arrives, so results never arrive out
    /// of order and overwrite a fresher list.
    private var searchTask: Task<Void, Never>?

    init() {}

    func register(_ provider: any LauncherActionProvider) {
        providers.append(provider)
    }

    func search(_ text: String) {
        let query = LauncherQuery(text)
        searchTask?.cancel()
        isSearching = true

        searchTask = Task { [providers] in
            var collected: [LauncherResult] = []

            await withTaskGroup(of: [LauncherResult].self) { group in
                for provider in providers {
                    group.addTask { await provider.results(for: query) }
                }
                for await providerResults in group {
                    collected.append(contentsOf: providerResults)
                }
            }

            guard !Task.isCancelled else { return }
            self.results = Self.rank(collected)
            self.isSearching = false
        }
    }

    func clear() {
        searchTask?.cancel()
        results = []
        isSearching = false
    }

    /// Sorts by relevance, then by section, then by title.
    ///
    /// Section is a tiebreak rather than the primary key so a strong application match can still
    /// outrank a weak metric match — otherwise typing an app's exact name would leave it below
    /// every metric that vaguely matched.
    nonisolated static func rank(_ results: [LauncherResult]) -> [LauncherResult] {
        results
            .sorted { left, right in
                if left.relevance != right.relevance { return left.relevance > right.relevance }
                if left.kind.sortIndex != right.kind.sortIndex {
                    return left.kind.sortIndex < right.kind.sortIndex
                }
                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
            .prefix(resultLimit)
            .map { $0 }
    }
}

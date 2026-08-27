import Foundation

/// Clipboard history as launcher results.
///
/// The whole of Phase 6's launcher integration: the search service, ranking and UI needed no
/// changes, because `LauncherAction` already had a `.copyToPasteboard` case and the provider
/// protocol was designed for exactly this.
@MainActor
final class ClipboardActionProvider: LauncherActionProvider {
    nonisolated let identifier = "clipboard"

    private let clipboard: ClipboardService

    /// Entries offered when the user has typed nothing. A launcher opened blank should suggest a
    /// few recent items, not dump the entire history.
    private static let unpromptedSuggestions = 5

    init(clipboard: ClipboardService) {
        self.clipboard = clipboard
    }

    nonisolated func results(for query: LauncherQuery) async -> [LauncherResult] {
        await MainActor.run { buildResults(for: query) }
    }

    private func buildResults(for query: LauncherQuery) -> [LauncherResult] {
        let matches = clipboard.search(query.normalized)
        let limited = query.isEmpty ? Array(matches.prefix(Self.unpromptedSuggestions)) : matches

        return limited.enumerated().map { index, item in
            LauncherResult(
                id: "clipboard.\(item.id.uuidString)",
                title: item.preview,
                subtitle: Self.relativeDescription(for: item.copiedAt),
                kind: .clipboard,
                symbolName: item.content.symbolName,
                // Recency is the tiebreak within the clipboard: for equal text relevance the
                // newer entry is almost always the one wanted.
                relevance: relevance(for: item, query: query, position: index),
                action: .copyToPasteboard(item.content.plainText)
            )
        }
    }

    private func relevance(for item: ClipboardItem, query: LauncherQuery, position: Int) -> Double {
        guard !query.isEmpty else {
            // Unprompted: rank below commands and metrics, newest first, so clipboard entries
            // never push the machine's state off the top of a blank launcher.
            return 0.30 - Double(position) * 0.01
        }
        let score = FuzzyMatcher.score(query: query.normalized, candidate: item.content.plainText) ?? 0
        return score - Double(position) * 0.001
    }

    private static func relativeDescription(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Copied " + formatter.localizedString(for: date, relativeTo: .now)
    }
}

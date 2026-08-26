import Foundation

/// Scores how well a candidate string matches a query.
///
/// Deliberately simple and explainable rather than a clever edit-distance metric: users expect
/// typing "sa" to surface "Safari" ahead of "Messages", and a tiered rule set produces that
/// predictably. Returns `nil` when there is no match at all, so callers can filter and rank in
/// one pass.
nonisolated enum FuzzyMatcher {
    /// Relevance in 0...1, or `nil` if `candidate` does not match `query`.
    static func score(query rawQuery: String, candidate: String) -> Double? {
        // Both sides are lowercased here rather than trusting the caller. `LauncherQuery` already
        // normalises, but a matcher that silently returns nil for an uppercase query is a trap
        // for the next caller.
        let query = rawQuery.lowercased()
        guard !query.isEmpty else { return 0.5 }

        let haystack = candidate.lowercased()
        guard !haystack.isEmpty else { return nil }

        if haystack == query { return 1.0 }
        if haystack.hasPrefix(query) {
            // Shorter candidates win among prefix matches: "Mail" beats "Mailbox Pro" for "mail".
            return 0.9 - lengthPenalty(query: query, candidate: haystack) * 0.1
        }
        // A match at a word boundary — "act" finding "Activity Monitor".
        if haystack.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .contains(where: { $0.hasPrefix(query) }) {
            return 0.75 - lengthPenalty(query: query, candidate: haystack) * 0.1
        }
        if haystack.contains(query) {
            return 0.6 - lengthPenalty(query: query, candidate: haystack) * 0.1
        }
        // Last resort: characters appearing in order but not contiguously ("actmon").
        if isSubsequence(query, of: haystack) {
            return 0.4 - lengthPenalty(query: query, candidate: haystack) * 0.1
        }
        return nil
    }

    /// 0 when the candidate is the same length as the query, approaching 1 as it grows.
    private static func lengthPenalty(query: String, candidate: String) -> Double {
        let extra = Double(max(0, candidate.count - query.count))
        return extra / (extra + 12)
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var index = haystack.startIndex
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return false }
            index = haystack.index(after: found)
        }
        return true
    }
}

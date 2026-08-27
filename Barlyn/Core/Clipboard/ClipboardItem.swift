import Foundation

/// What a clipboard entry holds.
///
/// An enum so images, files and rich text can be added as cases without changing the history
/// store, the search provider or the UI — they will carry a reference to a file on disk rather
/// than inline bytes, which is why the payload is deliberately not just `Data`.
nonisolated enum ClipboardContent: Codable, Hashable, Sendable {
    case text(String)
    case url(URL)

    /// Plain-text form, used for searching, previewing and writing back to the pasteboard.
    var plainText: String {
        switch self {
        case .text(let value): value
        case .url(let url): url.absoluteString
        }
    }

    var symbolName: String {
        switch self {
        case .text: "doc.text"
        case .url: "link"
        }
    }
}

/// One entry in the clipboard history.
///
/// Note what is *not* here: no raw pasteboard data, no owning-process handle. The history keeps
/// the minimum needed to show and restore an entry.
nonisolated struct ClipboardItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let content: ClipboardContent
    var copiedAt: Date

    /// Bundle identifier of the app that was frontmost when the entry was captured.
    ///
    /// **A heuristic, not the truth.** macOS does not report which process owns a pasteboard
    /// entry, so this is only "what was in front at the time". It is stored for a future
    /// per-app ignore list and is never presented as authoritative.
    let sourceBundleIdentifier: String?

    init(
        id: UUID = UUID(),
        content: ClipboardContent,
        copiedAt: Date = .now,
        sourceBundleIdentifier: String? = nil
    ) {
        self.id = id
        self.content = content
        self.copiedAt = copiedAt
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }

    /// Single-line preview. Collapses whitespace so a multi-line snippet stays one row.
    var preview: String {
        let collapsed = content.plainText
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return collapsed.count > 120 ? String(collapsed.prefix(120)) + "…" : collapsed
    }

    /// True when the entry carries nothing worth keeping.
    var isEmpty: Bool {
        content.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

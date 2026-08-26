import Foundation

/// What a launcher result does when the user presses Return.
///
/// An enum rather than a closure so results stay `Sendable` value types that can cross actors,
/// be compared in tests, and be ranked and cached without capturing UI state. Execution lives in
/// one place (`LauncherActionRunner`) instead of being scattered through providers.
nonisolated enum LauncherAction: Sendable, Hashable {
    case openWindow(WindowID)
    case openSettings
    case launchApplication(URL)
    case copyToPasteboard(String)
    case quitApp
    /// Informational rows, such as a live metric reading. Selecting one does nothing.
    case none
}

/// Grouping used for section headers and for ranking ties.
nonisolated enum LauncherResultKind: String, Sendable, Hashable, CaseIterable {
    case metric
    case command
    case application

    var displayName: String {
        switch self {
        case .metric: "System"
        case .command: "Commands"
        case .application: "Applications"
        }
    }

    /// Section order. Metrics first because they are informational and cheap to scan; the
    /// launcher doubles as a system readout.
    var sortIndex: Int {
        switch self {
        case .metric: 0
        case .command: 1
        case .application: 2
        }
    }
}

/// One row in the launcher.
nonisolated struct LauncherResult: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let kind: LauncherResultKind
    /// SF Symbol, used when there is no file icon.
    let symbolName: String
    /// File path whose icon should be shown instead of `symbolName` (applications).
    let iconPath: String?
    /// 0...1, higher sorts first. Set by the matcher, not by providers.
    let relevance: Double
    let action: LauncherAction

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        kind: LauncherResultKind,
        symbolName: String,
        iconPath: String? = nil,
        relevance: Double,
        action: LauncherAction
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.symbolName = symbolName
        self.iconPath = iconPath
        self.relevance = relevance
        self.action = action
    }
}

/// A search request.
nonisolated struct LauncherQuery: Sendable, Hashable {
    let text: String
    /// Lowercased and whitespace-trimmed, computed once rather than in every provider.
    let normalized: String

    init(_ text: String) {
        self.text = text
        self.normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isEmpty: Bool { normalized.isEmpty }
}

/// Supplies launcher results.
///
/// The extension point for everything the launcher will eventually search: applications, system
/// metrics, commands, clipboard history (Phase 6), window actions (Phase 7). A provider knows how
/// to find its own results and nothing about the UI.
nonisolated protocol LauncherActionProvider: Sendable {
    var identifier: String { get }
    /// Results for a query. An empty query should return the provider's default suggestions, or
    /// nothing if it has none worth showing unprompted.
    func results(for query: LauncherQuery) async -> [LauncherResult]
}

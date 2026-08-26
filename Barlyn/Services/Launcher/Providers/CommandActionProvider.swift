import Foundation

/// Barlyn's own commands.
nonisolated struct CommandActionProvider: LauncherActionProvider {
    let identifier = "commands"

    private struct Command {
        let id: String
        let title: String
        let subtitle: String
        let symbolName: String
        let action: LauncherAction
        /// Extra words that should match this command without appearing in its title, so
        /// "preferences" finds Settings.
        let aliases: [String]
    }

    private static let commands: [Command] = [
        Command(
            id: "command.dashboard",
            title: "Open Dashboard",
            subtitle: "Live system metrics",
            symbolName: "square.grid.2x2",
            action: .openWindow(.dashboard),
            aliases: ["metrics", "monitor", "stats"]
        ),
        Command(
            id: "command.settings",
            title: "Open Settings",
            subtitle: "Configure Barlyn",
            symbolName: "gearshape",
            action: .openSettings,
            aliases: ["preferences", "config", "options"]
        ),
        Command(
            id: "command.quit",
            title: "Quit Barlyn",
            subtitle: "Stop monitoring and exit",
            symbolName: "power",
            action: .quitApp,
            aliases: ["exit", "close"]
        ),
    ]

    func results(for query: LauncherQuery) async -> [LauncherResult] {
        Self.commands.compactMap { command in
            // Score against the title and every alias, keeping the best. A command should rank
            // on its strongest reason to appear, not on whichever field was checked last.
            let candidates = [command.title] + command.aliases
            let best = candidates.compactMap { FuzzyMatcher.score(query: query.normalized, candidate: $0) }.max()
            guard let relevance = best else { return nil }

            return LauncherResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                kind: .command,
                symbolName: command.symbolName,
                relevance: relevance,
                action: command.action
            )
        }
    }
}

import Foundation
import OSLog

/// Installed applications.
///
/// Enumerating `/Applications` and friends is one of the capabilities the App Sandbox would deny
/// (ADR-001), so this provider is a direct consequence of that decision.
///
/// An `actor` because the directory scan is file I/O that must not run on the main thread, and
/// because the result is cached: the catalogue is built once and refreshed lazily, so typing in
/// the launcher never touches the filesystem.
actor ApplicationActionProvider: LauncherActionProvider {
    nonisolated let identifier = "applications"

    private struct Application: Sendable {
        let name: String
        let url: URL
    }

    /// Directories macOS installs apps into. `~/Applications` is included because per-user
    /// installs are common and invisible to a scan of `/Applications` alone.
    ///
    /// `CoreServices` is included because Finder lives there and nowhere else — a launcher that
    /// cannot find Finder is obviously broken. It also holds ~117 background agents
    /// (`AirPlayUIAgent`, `BluetoothUIService`…), which `isUserFacing` filters out.
    private static let searchPaths: [URL] = {
        var paths = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
        ]
        if let home = FileManager.default.homeDirectoryForCurrentUser as URL? {
            paths.append(home.appending(path: "Applications"))
        }
        return paths
    }()

    /// How long a cached catalogue is trusted. Applications are installed rarely; rescanning on
    /// every keystroke would be pure waste.
    private static let cacheLifetime: Duration = .seconds(300)

    private var cache: [Application]?
    private var cachedAt: ContinuousClock.Instant?

    init() {}

    func results(for query: LauncherQuery) async -> [LauncherResult] {
        // With no query, listing every installed app would bury the metrics and commands that
        // make the launcher useful at a glance.
        guard !query.isEmpty else { return [] }

        return applications().compactMap { app in
            guard let relevance = FuzzyMatcher.score(query: query.normalized, candidate: app.name) else {
                return nil
            }
            return LauncherResult(
                id: "app.\(app.url.path)",
                title: app.name,
                subtitle: "Application",
                kind: .application,
                symbolName: "app",
                iconPath: app.url.path,
                relevance: relevance,
                action: .launchApplication(app.url)
            )
        }
    }

    /// Whether an app is something a person would launch, as opposed to a background agent.
    ///
    /// `LSUIElement` and `LSBackgroundOnly` are the flags macOS itself uses to keep an app out of
    /// the Dock and the app switcher, so honouring them is the same rule the system applies —
    /// not a hand-maintained blocklist that would rot with every OS release. Barlyn is itself
    /// `LSUIElement`, so it correctly excludes itself.
    ///
    /// The plist is read directly rather than through `Bundle`, which caches and is much slower
    /// across hundreds of apps. The whole scan is cached, so this runs rarely.
    private static func isUserFacing(_ url: URL) -> Bool {
        let plistURL = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            // Unreadable Info.plist: include it rather than hide a real app on a guess.
            return true
        }

        // Both keys appear as either Bool or the strings "1"/"YES" in the wild.
        func flag(_ key: String) -> Bool {
            if let value = plist[key] as? Bool { return value }
            if let value = plist[key] as? String { return value == "1" || value.uppercased() == "YES" }
            return false
        }
        return !flag("LSUIElement") && !flag("LSBackgroundOnly")
    }

    private func applications() -> [Application] {
        if let cache, let cachedAt, ContinuousClock.now - cachedAt < Self.cacheLifetime {
            return cache
        }

        let clock = ContinuousClock()
        let start = clock.now
        var found: [String: Application] = [:]

        for directory in Self.searchPaths {
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in contents ?? [] where url.pathExtension == "app" {
                guard Self.isUserFacing(url) else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                // Keyed by name so the same app present in two search paths appears once.
                found[name] = Application(name: name, url: url)
            }
        }

        let applications = found.values.sorted { $0.name < $1.name }
        cache = applications
        cachedAt = clock.now
        AppLog.launcher.notice(
            "Indexed \(applications.count) applications in \((clock.now - start).milliseconds) ms"
        )
        return applications
    }
}

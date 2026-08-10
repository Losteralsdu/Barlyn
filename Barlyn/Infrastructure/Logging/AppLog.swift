import OSLog

/// Unified Logging entry points, one `Logger` per subsystem area.
///
/// Categories are stable strings because they are the filter surface for
/// `log stream --predicate 'subsystem == "LSchirmer.Barlyn"'` during field debugging.
///
/// Privacy: os_log redacts interpolated values by default. Never override that with
/// `privacy: .public` for anything derived from clipboard contents, window titles,
/// file paths or credentials.
nonisolated enum AppLog {
    static let app = Logger(subsystem: AppInfo.bundleIdentifier, category: "App")
    static let metrics = Logger(subsystem: AppInfo.bundleIdentifier, category: "SystemMetrics")
    static let temperature = Logger(subsystem: AppInfo.bundleIdentifier, category: "Temperature")
    static let battery = Logger(subsystem: AppInfo.bundleIdentifier, category: "Battery")
    static let clipboard = Logger(subsystem: AppInfo.bundleIdentifier, category: "Clipboard")
    static let windowManagement = Logger(subsystem: AppInfo.bundleIdentifier, category: "WindowManagement")
    static let shortcuts = Logger(subsystem: AppInfo.bundleIdentifier, category: "Shortcuts")
    static let permissions = Logger(subsystem: AppInfo.bundleIdentifier, category: "Permissions")
    static let persistence = Logger(subsystem: AppInfo.bundleIdentifier, category: "Persistence")
    static let launcher = Logger(subsystem: AppInfo.bundleIdentifier, category: "QuickLauncher")
}

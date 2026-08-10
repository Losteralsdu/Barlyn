import Foundation

/// Static facts about the running bundle.
///
/// Everything that would otherwise be a string literal scattered across the code base
/// (bundle identifier, marketing version, log subsystem) is resolved here exactly once.
nonisolated enum AppInfo {
    /// Fallback matches `PRODUCT_BUNDLE_IDENTIFIER`. `Bundle.main.bundleIdentifier` is nil
    /// when code runs outside an app bundle, which is the case for the test host in some
    /// configurations, so a literal fallback keeps logging functional there.
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "LSchirmer.Barlyn"

    static let displayName = "Barlyn"

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"

    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"

    static var versionDescription: String { "\(version) (\(build))" }
}

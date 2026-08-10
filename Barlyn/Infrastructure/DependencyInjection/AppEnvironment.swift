import Foundation
import SwiftUI
import OSLog

/// The composition root.
///
/// Every service is constructed here and handed down through the SwiftUI environment. Services
/// never reach for each other via singletons, which is what keeps them substitutable in tests
/// and keeps the dependency graph visible in one file.
///
/// Construction is split from bootstrapping deliberately: `init` is synchronous so SwiftUI can
/// create the environment during `App` initialisation, while `bootstrap()` performs the async
/// hardware-capability probing that decides which metric providers actually exist on this Mac.
@MainActor
@Observable
final class AppEnvironment {
    let preferences: PreferenceStore
    let metricRegistry: MetricRegistry
    let metricSampler: MetricSampler
    let metricFormatter: MetricFormatter

    private(set) var isBootstrapped = false

    init(
        preferences: PreferenceStore,
        metricRegistry: MetricRegistry = MetricRegistry(),
        metricFormatter: MetricFormatter = MetricFormatter()
    ) {
        self.preferences = preferences
        self.metricRegistry = metricRegistry
        self.metricSampler = MetricSampler(registry: metricRegistry)
        self.metricFormatter = metricFormatter
    }

    /// Environment backed by the user's real settings and real system APIs.
    static func live() -> AppEnvironment {
        AppEnvironment(preferences: PreferenceStore(storage: UserDefaultsPreferenceStorage()))
    }

    /// Environment with no persistence side effects, for tests and SwiftUI previews.
    static func ephemeral() -> AppEnvironment {
        AppEnvironment(
            preferences: PreferenceStore(storage: InMemoryPreferenceStorage()),
            metricFormatter: MetricFormatter(locale: Locale(identifier: "en_US_POSIX"))
        )
    }

    /// Registers every metric provider supported by this machine.
    ///
    /// Idempotent: safe to call from a SwiftUI `.task`, which may run more than once.
    func bootstrap() async {
        guard !isBootstrapped else { return }
        isBootstrapped = true

        await registerMetricProviders()

        AppLog.app.notice(
            "Barlyn \(AppInfo.versionDescription, privacy: .public) bootstrapped with \(self.metricRegistry.count) metrics"
        )
    }

    /// The single place where the app's metric catalogue is declared.
    ///
    /// Phase 3 extends this list; nothing else in the app needs to change for a new metric to
    /// appear in the menu bar, dashboard and Quick Launcher.
    private func registerMetricProviders() async {
        let providers: [any MetricProvider] = [
            UptimeMetricProvider(),
            LoadAverageMetricProvider(),
        ]

        for provider in providers {
            await metricRegistry.registerIfSupported(provider)
        }
    }
}

// MARK: - SwiftUI environment plumbing

extension EnvironmentValues {
    /// Views read services via `@Environment(\.appEnvironment)` rather than importing globals.
    @Entry var appEnvironment: AppEnvironment = .ephemeral()
}

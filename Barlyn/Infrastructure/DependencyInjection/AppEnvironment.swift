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

    /// Second-wave registration for providers that need slow hardware probing.
    private var deferredRegistration: Task<Void, Never>?

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
    ///
    /// Registration happens in two waves. Providers whose support check is effectively free are
    /// registered before this returns, so the UI has real metrics immediately. Providers that
    /// need expensive hardware probing are registered afterwards from a background task and
    /// appear when confirmed — `MetricRegistry` is `@Observable`, so the UI updates itself.
    /// Blocking launch on the slow probe would cost half a second of dead window.
    func bootstrap() async {
        guard !isBootstrapped else { return }
        isBootstrapped = true

        let powerSource = PowerSourceService()

        // Registration order is the default display order.
        let immediate: [any MetricProvider] = [
            CPUUsageMetricProvider(),
            MemoryMetricProvider(),
            ThermalPressureMetricProvider(),
            BatteryPowerMetricProvider(powerSource: powerSource),
            SystemPowerMetricProvider(powerSource: powerSource),
            LoadAverageMetricProvider(),
            UptimeMetricProvider(),
        ]
        for provider in immediate {
            await metricRegistry.registerIfSupported(provider)
        }

        AppLog.app.notice(
            "Barlyn \(AppInfo.versionDescription, privacy: .public) bootstrapped with \(self.metricRegistry.count) metrics"
        )

        deferredRegistration = Task { [metricRegistry] in
            // SMC key discovery enumerates every key the controller exposes (~3500 on the
            // development Mac, ~480 ms). It runs once per process and is cached inside
            // `SMCService`; only the selected sensors are re-read per sample.
            let smc = SMCService()
            await metricRegistry.registerIfSupported(CPUTemperatureMetricProvider(smc: smc))
        }
    }

    /// Waits for hardware-probed providers to finish registering.
    ///
    /// Exists for tests and for any UI that must not report "unsupported" before probing has
    /// actually finished. Normal UI does not need it — the registry is observable.
    func awaitFullRegistration() async {
        await deferredRegistration?.value
    }
}

// MARK: - SwiftUI environment plumbing

extension EnvironmentValues {
    /// Views read services via `@Environment(\.appEnvironment)` rather than importing globals.
    @Entry var appEnvironment: AppEnvironment = .ephemeral()
}

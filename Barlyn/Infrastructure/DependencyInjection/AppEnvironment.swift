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
    let menuBarConfiguration: MenuBarConfiguration
    let dashboardConfiguration: DashboardConfiguration
    let metricHistory: MetricHistory
    let launcherSearch: LauncherSearchService
    let quickLauncher: QuickLauncherController
    let hotkeyService: HotkeyService
    let clipboard: ClipboardService

    private(set) var isBootstrapped = false

    /// Second-wave registration for providers that need slow hardware probing.
    private var deferredRegistration: Task<Void, Never>?

    init(
        preferences: PreferenceStore,
        metricRegistry: MetricRegistry = MetricRegistry(),
        metricFormatter: MetricFormatter = MetricFormatter(),
        clipboardStorage: (any ClipboardHistoryStorage)? = nil
    ) {
        self.preferences = preferences
        self.metricRegistry = metricRegistry
        let history = MetricHistory()
        self.metricHistory = history
        let sampler = MetricSampler(registry: metricRegistry, history: history)
        self.metricSampler = sampler
        self.metricFormatter = metricFormatter
        self.menuBarConfiguration = MenuBarConfiguration(
            preferences: preferences,
            registry: metricRegistry,
            sampler: sampler
        )
        self.dashboardConfiguration = DashboardConfiguration(
            preferences: preferences,
            registry: metricRegistry
        )

        // Falls back to in-memory when Application Support is unavailable, so a storage failure
        // degrades to a session-only history rather than crashing the app.
        self.clipboard = ClipboardService(
            storage: clipboardStorage ?? FileClipboardHistoryStorage() ?? InMemoryClipboardHistoryStorage(),
            preferences: preferences
        )

        let search = LauncherSearchService()
        self.launcherSearch = search
        self.hotkeyService = HotkeyService()
        self.quickLauncher = QuickLauncherController(
            searchService: search,
            sampler: sampler,
            registry: metricRegistry
        )

        // The launcher panel hosts a SwiftUI tree that needs this environment, but the
        // environment owns the launcher. A closure breaks the cycle without either holding the
        // other strongly at construction time.
        quickLauncher.environmentProvider = { [unowned self] in self }
    }

    /// Environment backed by the user's real settings and real system APIs.
    static func live() -> AppEnvironment {
        AppEnvironment(preferences: PreferenceStore(storage: UserDefaultsPreferenceStorage()))
    }

    /// Environment with no persistence side effects, for tests and SwiftUI previews.
    ///
    /// Clipboard storage is in-memory too: a test must never read or write the user's real
    /// clipboard history file.
    static func ephemeral() -> AppEnvironment {
        AppEnvironment(
            preferences: PreferenceStore(storage: InMemoryPreferenceStorage()),
            metricFormatter: MetricFormatter(locale: Locale(identifier: "en_US_POSIX")),
            clipboardStorage: InMemoryClipboardHistoryStorage()
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

        // Menu bar demand can be applied as soon as the first wave exists; SMC-backed metrics
        // are re-applied when they arrive below.
        menuBarConfiguration.apply()

        registerLauncherProviders()
        applyLauncherHotkey()
        clipboard.applyMonitoringPreference()

        deferredRegistration = Task { [metricRegistry, menuBarConfiguration] in
            // SMC key discovery enumerates every key the controller exposes (~3500 on the
            // development Mac, ~480 ms). It runs once per process and is cached inside
            // `SMCService`, and one instance is shared by every SMC-backed provider so the cost
            // is paid exactly once.
            let smc = SMCService()
            for provider in [
                CPUTemperatureMetricProvider(smc: smc) as any MetricProvider,
                GPUTemperatureMetricProvider(smc: smc),
                FanSpeedMetricProvider(smc: smc),
            ] {
                await metricRegistry.registerIfSupported(provider)
            }
            // A user may have selected an SMC metric for the menu bar; its demand can only be
            // honoured now that it is registered.
            menuBarConfiguration.apply()
        }
    }

    /// The launcher's search sources. Phase 6 adds clipboard history and Phase 7 window actions
    /// by appending here; neither the search service nor the UI changes.
    private func registerLauncherProviders() {
        launcherSearch.register(
            MetricActionProvider(
                registry: metricRegistry,
                sampler: metricSampler,
                formatter: metricFormatter
            )
        )
        launcherSearch.register(CommandActionProvider())
        launcherSearch.register(ClipboardActionProvider(clipboard: clipboard))
        launcherSearch.register(ApplicationActionProvider())
    }

    /// Registers the global shortcut that opens the launcher.
    ///
    /// A failure here is reported rather than swallowed: a launcher whose shortcut silently does
    /// nothing is worse than one that says why.
    func applyLauncherHotkey() {
        guard preferences[PreferenceKeys.launcherEnabled] else {
            hotkeyService.unregister(.quickLauncher)
            return
        }

        let combination = preferences[PreferenceKeys.launcherHotkey]
        do {
            try hotkeyService.register(combination, for: .quickLauncher) { [weak self] in
                self?.quickLauncher.toggle()
            }
        } catch {
            AppLog.shortcuts.error(
                "Could not register launcher hotkey: \(error.diagnosticDescription, privacy: .public)"
            )
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

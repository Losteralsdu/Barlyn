import Carbon.HIToolbox
import Foundation
import Testing
@testable import Barlyn

@Suite("Fuzzy matching")
struct FuzzyMatcherTests {

    @Test("Exact matches outrank prefixes, which outrank contains")
    func tierOrdering() throws {
        let exact = try #require(FuzzyMatcher.score(query: "mail", candidate: "Mail"))
        let prefix = try #require(FuzzyMatcher.score(query: "mail", candidate: "Mailbox"))
        let contains = try #require(FuzzyMatcher.score(query: "mail", candidate: "Voicemail"))

        #expect(exact > prefix)
        #expect(prefix > contains)
    }

    @Test("Shorter candidates win among equal-tier matches")
    func lengthPreference() throws {
        // Typing "mail" should surface Mail before Mailbox Professional Edition.
        let short = try #require(FuzzyMatcher.score(query: "mail", candidate: "Mailbox"))
        let long = try #require(FuzzyMatcher.score(query: "mail", candidate: "Mailbox Professional Edition"))
        #expect(short > long)
    }

    @Test("Word-boundary matches beat mid-word ones")
    func wordBoundary() throws {
        let boundary = try #require(FuzzyMatcher.score(query: "mon", candidate: "Activity Monitor"))
        let midWord = try #require(FuzzyMatcher.score(query: "mon", candidate: "Salmon"))
        #expect(boundary > midWord)
    }

    @Test("Subsequences match but rank last")
    func subsequence() throws {
        let subsequence = try #require(FuzzyMatcher.score(query: "actmon", candidate: "Activity Monitor"))
        let contains = try #require(FuzzyMatcher.score(query: "monitor", candidate: "Activity Monitor"))
        #expect(subsequence < contains)
    }

    @Test("Non-matches return nil rather than a low score")
    func noMatch() {
        // nil lets callers filter and rank in one pass instead of guessing a cutoff.
        #expect(FuzzyMatcher.score(query: "zzz", candidate: "Activity Monitor") == nil)
    }

    @Test("An empty query matches everything neutrally")
    func emptyQuery() {
        #expect(FuzzyMatcher.score(query: "", candidate: "Anything") != nil)
    }

    @Test("Matching ignores case")
    func caseInsensitive() {
        #expect(FuzzyMatcher.score(query: "safari", candidate: "Safari") != nil)
        #expect(FuzzyMatcher.score(query: "SAFARI", candidate: "safari".uppercased()) != nil)
    }
}

@Suite("Launcher ranking")
struct LauncherRankingTests {

    private func result(
        _ title: String,
        kind: LauncherResultKind,
        relevance: Double
    ) -> LauncherResult {
        LauncherResult(
            id: "\(kind.rawValue).\(title)",
            title: title,
            kind: kind,
            symbolName: "circle",
            relevance: relevance,
            action: .none
        )
    }

    @Test("Relevance dominates section order")
    func relevanceFirst() {
        // A strong application match must beat a weak metric match, or typing an app's exact
        // name would leave it buried under every vaguely-matching metric.
        let ranked = LauncherSearchService.rank([
            result("Memory Usage", kind: .metric, relevance: 0.4),
            result("Safari", kind: .application, relevance: 0.95),
        ])
        #expect(ranked.first?.title == "Safari")
    }

    @Test("Section breaks ties in relevance")
    func sectionTiebreak() {
        let ranked = LauncherSearchService.rank([
            result("Some App", kind: .application, relevance: 0.7),
            result("Some Metric", kind: .metric, relevance: 0.7),
            result("Some Command", kind: .command, relevance: 0.7),
        ])
        #expect(ranked.map(\.kind) == [.metric, .command, .application])
    }

    @Test("Results are capped")
    func limit() {
        let many = (0..<200).map { result("App \($0)", kind: .application, relevance: 0.5) }
        #expect(LauncherSearchService.rank(many).count == LauncherSearchService.resultLimit)
    }
}

@Suite("Launcher providers")
struct LauncherProviderTests {

    @Test("Commands match their aliases, not just their titles")
    func commandAliases() async {
        let provider = CommandActionProvider()
        // "preferences" appears nowhere in "Open Settings".
        let results = await provider.results(for: LauncherQuery("preferences"))
        #expect(results.contains { $0.action == .openSettings })
    }

    @Test("Commands expose the actions they claim")
    func commandActions() async {
        let results = await CommandActionProvider().results(for: LauncherQuery(""))
        #expect(results.contains { $0.action == .openWindow(.dashboard) })
        #expect(results.contains { $0.action == .quitApp })
        #expect(results.allSatisfy { $0.kind == .command })
    }

    @Test("Applications return nothing for an empty query")
    func applicationsNeedAQuery() async {
        // Listing every installed app unprompted would bury the metrics and commands that make
        // the launcher useful at a glance.
        let results = await ApplicationActionProvider().results(for: LauncherQuery(""))
        #expect(results.isEmpty)
    }

    @Test("Applications are found on this Mac and carry a launch action")
    func applicationsAreIndexed() async {
        // Finder exists on every Mac, in /System/Applications.
        let results = await ApplicationActionProvider().results(for: LauncherQuery("finder"))
        let finder = results.first { $0.title == "Finder" }
        #expect(finder != nil, "Finder should be discoverable in the standard search paths")

        if case .launchApplication(let url)? = finder?.action {
            #expect(url.pathExtension == "app")
        } else {
            Issue.record("Finder result should carry a launchApplication action")
        }
        #expect(finder?.iconPath != nil, "Applications should render their real icon")
    }

    @Test("Metric rows are informational, never executable")
    @MainActor
    func metricRowsDoNothing() async {
        let environment = AppEnvironment.ephemeral()
        environment.metricRegistry.register(UptimeMetricProvider())

        let provider = MetricActionProvider(
            registry: environment.metricRegistry,
            sampler: environment.metricSampler,
            formatter: environment.metricFormatter
        )
        let results = await provider.results(for: LauncherQuery("uptime"))

        #expect(results.count == 1)
        // A metric is something to read, not something to run.
        #expect(results.first?.action == LauncherAction.none)
        #expect(results.first?.kind == .metric)
    }
}

@Suite("Key combinations")
struct KeyCombinationTests {

    @Test("Default launcher shortcut is Option+Space")
    func defaultShortcut() {
        let combination = KeyCombination.optionSpace
        #expect(combination.displayString == "⌥Space")
        #expect(combination.modifiers == .option)
        #expect(combination.keyCode == UInt16(kVK_Space))
    }

    @Test("Modifiers render in Apple's canonical order")
    func modifierOrder() {
        let all = KeyCombination(
            keyCode: UInt16(kVK_ANSI_K),
            modifiers: [.command, .shift, .option, .control]
        )
        #expect(all.displayString == "⌃⌥⇧⌘K")
    }

    @Test("Carbon modifier bits differ from the AppKit ones and are mapped explicitly")
    func carbonModifiers() {
        #expect(KeyCombination(keyCode: 0, modifiers: .command).carbonModifiers == UInt32(cmdKey))
        #expect(KeyCombination(keyCode: 0, modifiers: .option).carbonModifiers == UInt32(optionKey))
        #expect(KeyCombination(keyCode: 0, modifiers: .control).carbonModifiers == UInt32(controlKey))
        #expect(KeyCombination(keyCode: 0, modifiers: .shift).carbonModifiers == UInt32(shiftKey))

        let combined = KeyCombination(keyCode: 0, modifiers: [.command, .shift]).carbonModifiers
        #expect(combined == UInt32(cmdKey) | UInt32(shiftKey))
    }

    @Test("A modifier-less combination is rejected as a global shortcut")
    func requiresModifiers() {
        // Without a modifier it would fire while the user types anywhere on the system.
        #expect(KeyCombination(keyCode: UInt16(kVK_Space), modifiers: []).isValidGlobalHotkey == false)
        #expect(KeyCombination.optionSpace.isValidGlobalHotkey)
    }

    @Test("Shortcuts survive a Codable round trip")
    func codableRoundTrip() throws {
        let original = KeyCombination(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .option])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyCombination.self, from: data)
        #expect(decoded == original)
        #expect(decoded.displayString == "⌥⌘J")
    }
}

/// `.serialized` because global hotkeys are process-wide OS state, not per-instance: two tests
/// registering concurrently collide in Carbon regardless of using separate `HotkeyService`
/// objects. Each test also uses a distinct key so a leaked registration cannot poison another.
@Suite("Hotkey service", .serialized)
@MainActor
struct HotkeyServiceTests {

    @Test("Registering a modifier-less combination is refused")
    func rejectsMissingModifiers() {
        let service = HotkeyService()
        #expect(throws: HotkeyError.missingModifiers) {
            try service.register(
                KeyCombination(keyCode: UInt16(kVK_F13), modifiers: []),
                for: .quickLauncher
            ) {}
        }
    }

    @Test("A registered combination is reported back")
    func registrationIsRecorded() throws {
        let service = HotkeyService()
        // F13 with a modifier: unlikely to collide with anything the machine already owns.
        let combination = KeyCombination(keyCode: UInt16(kVK_F13), modifiers: [.control, .option])

        try service.register(combination, for: .quickLauncher) {}
        #expect(service.combination(for: .quickLauncher) == combination)

        service.unregister(.quickLauncher)
        #expect(service.combination(for: .quickLauncher) == nil)
    }

    @Test("Re-registering the same id replaces rather than collides")
    func reregistrationReplaces() throws {
        let service = HotkeyService()
        let first = KeyCombination(keyCode: UInt16(kVK_F16), modifiers: [.control, .option])
        let second = KeyCombination(keyCode: UInt16(kVK_F17), modifiers: [.control, .option])

        try service.register(first, for: .quickLauncher) {}
        // Changing the shortcut in Settings is the common path; the old registration must be
        // released first or the new one collides with it.
        try service.register(second, for: .quickLauncher) {}
        #expect(service.combination(for: .quickLauncher) == second)

        service.unregisterAll()
    }

    @Test("A combination already held by another Barlyn shortcut is refused")
    func detectsInProcessConflict() throws {
        let service = HotkeyService()
        let combination = KeyCombination(keyCode: UInt16(kVK_F15), modifiers: [.control, .option])
        let other = HotkeyService.HotkeyID("test.other")

        try service.register(combination, for: .quickLauncher) {}
        // Carbon reports eventHotKeyExistsErr for this case — the one conflict class that can be
        // detected reliably. System-owned combinations cannot be detected at all.
        #expect(throws: HotkeyError.alreadyRegistered(combination: combination.displayString)) {
            try service.register(combination, for: other) {}
        }

        service.unregisterAll()
    }
}

@Suite("Launcher pipeline")
@MainActor
struct LauncherPipelineTests {

    /// Waits for the search service to settle, since providers run concurrently.
    private func awaitResults(_ service: LauncherSearchService) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline, service.isSearching {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("A real query flows through every registered provider and ranks")
    func endToEndSearch() async throws {
        let environment = AppEnvironment.ephemeral()
        await environment.bootstrap()

        environment.launcherSearch.search("settings")
        try await awaitResults(environment.launcherSearch)

        let results = environment.launcherSearch.results
        #expect(!results.isEmpty)
        // The Settings command should win: it is an exact-ish title match against a short title.
        #expect(results.first?.action == .openSettings)
        #expect(results.count <= LauncherSearchService.resultLimit)
    }

    @Test("An empty query shows metrics and commands but not the whole Applications folder")
    func emptyQueryIsUseful() async throws {
        let environment = AppEnvironment.ephemeral()
        await environment.bootstrap()

        environment.launcherSearch.search("")
        try await awaitResults(environment.launcherSearch)

        let kinds = Set(environment.launcherSearch.results.map(\.kind))
        #expect(kinds.contains(.metric), "Opening the launcher should show the machine's state")
        #expect(kinds.contains(.command))
        #expect(!kinds.contains(.application), "Listing every app unprompted would bury everything else")
    }

    @Test("Searching an installed application finds it and offers to launch it")
    func findsInstalledApplication() async throws {
        let environment = AppEnvironment.ephemeral()
        await environment.bootstrap()

        // Finder lives in /System/Library/CoreServices, not /System/Applications — a search path
        // that is easy to omit and would make the launcher visibly incomplete.
        environment.launcherSearch.search("finder")
        try await awaitResults(environment.launcherSearch)

        let finder = environment.launcherSearch.results.first { $0.title == "Finder" }
        #expect(finder != nil)
        #expect(finder?.kind == .application)
    }

    @Test("Background agents are excluded from application results")
    func excludesBackgroundAgents() async throws {
        let provider = ApplicationActionProvider()
        // A CoreServices agent marked LSUIElement; it must never appear as something to launch.
        let results = await provider.results(for: LauncherQuery("AirPlayUIAgent"))
        #expect(results.isEmpty)
    }

    @Test("A newer query replaces an older one rather than racing it")
    func laterQueryWins() async throws {
        let environment = AppEnvironment.ephemeral()
        await environment.bootstrap()

        environment.launcherSearch.search("finder")
        environment.launcherSearch.search("settings")
        try await awaitResults(environment.launcherSearch)

        // The in-flight search is cancelled, so stale results cannot overwrite fresher ones.
        #expect(environment.launcherSearch.results.contains { $0.action == .openSettings })
        #expect(!environment.launcherSearch.results.contains { $0.title == "Finder" })
    }
}

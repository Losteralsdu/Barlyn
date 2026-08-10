# Barlyn — Project Knowledge Base

> Persistent knowledge for Claude Code sessions. Update this file whenever architecture,
> constraints or verified API behaviour change. Do not rely on conversation history.

---

## 1. Purpose

Barlyn is a native macOS power-user suite: menu bar system monitor, dashboard, Spotlight-like
quick launcher, clipboard history, window management and a central global-shortcut system.

Personal use first, but built to commercial standards: local-first, privacy-preserving,
modular, testable, and cheap enough to run continuously for days.

**Core principle — technical honesty.** Never fabricate, estimate-without-labelling, or
mislabel a system value. Unavailable is a first-class, typed state (`MetricReading.unavailable`),
and the *source* of every number is carried in the model (`MetricProvenance`) all the way to the
UI. See ADR-004.

---

## 2. Environment (verified 2026-08-10)

| Item | Value |
|---|---|
| macOS | 26.5 (build 25F84) |
| Hardware | Apple Silicon, arm64, 15 cores, 24 GB RAM, 2 fans |
| Xcode | 26.6 (17F113) |
| Swift | 6.3.3 |
| Deployment target | macOS 26.5 |
| Swift language mode | 6 (`SWIFT_VERSION = 6.0`) |
| Default actor isolation | `MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION`) |
| Approachable concurrency | YES |
| Member import visibility | YES (upcoming feature — see §9) |
| App Sandbox | **NO** (see ADR-001) |
| Hardened Runtime | YES |
| Team / bundle ID |  / `LSchirmer.Barlyn` |
| Third-party dependencies | **none** |

**Xcode project uses `fileSystemSynchronizedGroups` (objectVersion 77).** Adding a `.swift` file
anywhere under `Barlyn/`, `BarlynTests/` or `BarlynUITests/` compiles it automatically — never
hand-edit `project.pbxproj` to add sources.

### Commands

```bash
xcodebuild -scheme Barlyn -configuration Debug -destination 'platform=macOS,arch=arm64' build
xcodebuild -scheme Barlyn -configuration Debug -destination 'platform=macOS,arch=arm64' test -only-testing:BarlynTests
```

Unified logging (`log show` breaks under zsh quoting; put it in a script file):

```bash
log show --predicate 'subsystem == "LSchirmer.Barlyn"' --last 5m --style compact --info
```

---

## 3. Directory structure

```
Barlyn/
├── App/                        Lifecycle only. No business logic.
│   ├── BarlynApp.swift         @main, scene graph, WindowID
│   └── AppDelegate.swift       AppKit hooks SwiftUI does not expose
├── Core/                       Pure logic. No system APIs, no SwiftUI. Fully unit-testable.
│   ├── Errors/                 BarlynError protocol, MetricError, PersistenceError, PermissionKind
│   └── Metrics/                Identifier, Unit, Value, Descriptor, Reading, Provider, Registry, Formatter
├── Infrastructure/             Cross-cutting concerns
│   ├── Configuration/          AppInfo, AppConfiguration (sampling bounds)
│   ├── Logging/                AppLog — one Logger per category
│   └── DependencyInjection/    AppEnvironment — the composition root
├── Services/                   Implementations that talk to the system
│   ├── Metrics/                MetricSampler + Providers/
│   └── Preferences/            PreferenceStorage, PreferenceKey, PreferenceStore
├── Features/                   UI, one folder per feature
│   └── Diagnostics/            FoundationStatusView (Phase 1 scaffold, replaced in Phase 4)
└── Assets.xcassets
```

Dependency direction is strictly one-way: `Features → Services → Core`, with `Infrastructure`
available to all. Core never imports SwiftUI.

---

## 4. Architecture

### Metric system (the extensibility spine)

```
MetricProvider (protocol, Sendable)
   ├── descriptor: MetricDescriptor   ← id, names, unit, category, interval, provenance
   ├── isSupported() async -> Bool    ← hardware probe; unsupported metrics are not registered
   └── read() async throws(MetricError) -> MetricReading
                 │
        MetricRegistry (@MainActor @Observable)   ← catalogue, registration-ordered
                 │
        MetricSampler (@MainActor @Observable)    ← demand-driven polling, one Task per metric
                 │
        MetricFormatter (nonisolated, locale-injected)
                 │
        Any UI: menu bar / dashboard / quick launcher
```

**Adding a metric = write a provider + append it to `AppEnvironment.registerMetricProviders()`.**
No UI, formatter or preference change is required. `FoundationStatusView` is written entirely
against `MetricDescriptor`, so it renders new metrics with zero edits — this is enforced by
construction, not convention.

Key types:

- `MetricIdentifier` — string-backed, not an enum (ADR-005). Persisted in preferences.
- `MetricReading` — `.available(MetricSnapshot)` | `.unavailable(MetricUnavailability)`.
- `MetricSnapshot.components: [MetricComponent]` — generic breakdown slot (CPU user/system/idle,
  memory used/total/wired). Avoids a bespoke model per metric.
- `MetricValue.isPlausible` / `MetricReading.checked(...)` — rejects sentinel garbage from
  undocumented sensors instead of publishing it.
- `MetricProvenance` — `.publicAPI` | `.undocumentedInterface` | `.derived`; drives UI caveats.

### Sampling and cost

`MetricSampler` polls only what a consumer has declared demand for
(`setDemand(_:for: .menuBar / .dashboard / .quickLauncher / .diagnostics)`). Demand from all
consumers is unioned; when the last consumer releases a metric its task is cancelled **and its
value discarded**, so a stale number can never be displayed. Intervals are clamped to
`AppConfiguration` bounds (floor 500 ms, ceiling 60 s).

### Dependency injection

`AppEnvironment` is the single composition root, injected via
`@Environment(\.appEnvironment)`. `init` is synchronous (SwiftUI needs it); async hardware
probing lives in `bootstrap()`, which is idempotent. `AppEnvironment.ephemeral()` gives tests
and previews an in-memory, side-effect-free graph. No singletons anywhere.

### Preferences

`PreferenceKey<Value>` binds name + type + default in one value. `PreferenceStore` is
`@Observable`, JSON-encodes uniformly, and is backed by a swappable `PreferenceStorage`
(`UserDefaultsPreferenceStorage` with a `barlyn.` prefix, or `InMemoryPreferenceStorage`).
Corrupt entries are logged, deleted and replaced by the default rather than silently swallowed.

---

## 5. Verified system API findings

Measured on this machine on 2026-08-10 with throwaway probes — not recalled from documentation.

### CPU
`host_processor_info(PROCESSOR_CPU_LOAD_INFO)` → per-core user/system/idle/nice **tick counters**
(cumulative). Usage requires a delta between two samples, so the provider must be an `actor`
holding previous ticks. `KERN_SUCCESS` confirmed, 15 cores. Must `vm_deallocate` the returned
array. `getloadavg(3)` works and is already used by `LoadAverageMetricProvider`.

### Memory
`host_statistics64(HOST_VM_INFO64)` confirmed. Page size **16384** on Apple Silicon — always read
`vm_kernel_page_size`, never assume 4096. Available fields: free, active, inactive, wired,
compressor (compressed), speculative, purgeable, external.
`ProcessInfo.physicalMemory` = 25769803776 (24 GiB).

**"Used memory" must be defined and documented.** Activity Monitor's "Memory Used" ≈
`active + wired + compressed` (excluding purgeable/external). Phase 3 must state which definition
is displayed rather than inventing one.

### Battery power — **available and reliable**
IORegistry service `AppleSmartBattery` exposes:

| Key | Observed | Meaning |
|---|---|---|
| `Amperage` | 0 | mA, **signed** (negative = discharging) |
| `Voltage` | 12444 | mV |
| `InstantAmperage` | 0 | mA, unsmoothed |
| `PowerTelemetryData.SystemPowerIn` | 5175 | **mW drawn from the wall/adapter** |
| `PowerTelemetryData.SystemVoltageIn` | 20079 | mV in |
| `PowerTelemetryData.BatteryPower` | 0 | mW battery-side |
| `AdapterDetails.Watts` | 92 | adapter maximum, not current draw |
| `ExternalConnected` / `IsCharging` / `FullyCharged` | 1 / 0 / 0 | state |
| `Temperature` | 3069 | **battery** temp, 0.01 °C → 30.69 °C. **Not CPU temperature.** |

Battery-side watts = `Amperage (mA) × Voltage (mV) / 1e6`. Distinguish battery power from system
input power in the UI — they are different quantities and users conflate them.
`IOPSCopyPowerSourcesInfo` (public) gives percentage/state/time-remaining but **no wattage**.

### CPU temperature — **available via SMC, with real caveats**
`IOServiceOpen` on `AppleSMC` **succeeded** from an unsandboxed process. 3485 keys enumerated.
Confirmed live readings (type `flt `, little-endian Float32):

- `Tp0*` (Tp00, Tp04, Tp08, Tp0C…) — P-core cluster die, 46–53 °C
- `Tm*`, `Ts0*` — other die/skin sensors, ~46–50 °C
- `Tg0*` — GPU cluster, ~47 °C
- `TB0T`/`TB1T`/`TB2T` — battery, ~33.8 °C
- `F0Ac` / `F1Ac` — **actual fan RPM** (2319 / 2504); `F0Mn`/`F0Mx` min/max
- `PSTR` 11.5 W, `PDTR` 18.0 W — power rails

**Caveats that must reach the user:**
1. Key→sensor mapping is **reverse-engineered community consensus**, not Apple documentation.
2. Key sets differ per chip generation and model — **never hard-code a key table**; enumerate at
   runtime via `#KEY` + `kSMCGetKeyFromIndex` and classify by prefix.
3. Some keys return sentinel garbage (`TTPD` = −306783232.0) or 0.0 for inactive channels
   (`Tz1*`). Range-check every value (`MetricValue.isPlausible`).
4. Requires an unsandboxed process (ADR-001).
5. Enumerating all 3485 keys costs ~7000 IOKit round trips — **do this once at startup and cache
   the discovered sensor list**; only re-read selected keys per interval.

Public alternative, always available, no caveats: `ProcessInfo.thermalState`
(nominal/fair/serious/critical) — verified working. Ship this as the guaranteed baseline.

### Misc verified
- `sysctl KERN_BOOTTIME` = wall-clock uptime (matches `uptime(1)`).
  `ProcessInfo.systemUptime` is `mach_absolute_time`-based and **does not advance during sleep** —
  it is "awake time", not uptime. `UptimeMetricProvider` uses `KERN_BOOTTIME`.
- `ProcessInfo.isLowPowerModeEnabled`, `activeProcessorCount` — fine.

### Not yet investigated (do before Phase 5/7)
Global hotkeys (Carbon `RegisterEventHotKey` is the intended approach — no permission needed,
still functional on Apple Silicon; `NSEvent` global monitors need Input Monitoring and cannot
consume events). Accessibility `AXUIElement` window control. `NSPasteboard.changeCount` polling.
`NSScreen` multi-display geometry.

---

## 6. Permissions

| Permission | Needed for | Status |
|---|---|---|
| Accessibility | Window management (Phase 7), reading focused window | Not yet requested |
| Input Monitoring | Possibly some shortcut scopes | Likely avoidable via Carbon hotkeys |
| — | System metrics, SMC, clipboard | **No permission required** (unsandboxed) |

Centralise in a `PermissionManager` (Phase 7). `PermissionKind` already exists in
`Core/Errors/BarlynError.swift` with System Settings deep links. Never scatter
`AXIsProcessTrusted()` calls through views.

---

## 7. Known limitations & risks

1. **No Mac App Store distribution** — consequence of disabling the sandbox (ADR-001).
   Distribution is Developer ID + notarization.
2. **SMC sensor naming is inferred**, not documented; may differ on other Macs and may break on
   future chips. Mitigation: runtime discovery, range checks, `MetricProvenance` in the UI.
3. **Nested git repository** — `Barlyn/` (the *source* folder) contains its own `.git` pointing at
   `github.com/Losteralsdu/Barlyn.git`, inside the outer repo at the project root. This appeared
   mid-session on 2026-08-09 and is **unresolved**; it also puts `README.md`/`.gitattributes`
   inside a synchronized group. Needs a human decision (§11).
4. **`@Observable` granularity in `PreferenceStore`** — the whole cache dictionary is one
   observation unit, so any write invalidates readers of any key. Fine at human-speed settings;
   never put high-frequency values there.
5. Visual verification of the running UI was not possible from the agent shell (no Screen
   Recording / Accessibility grant). Launch, window geometry, logs and the full data pipeline are
   verified; pixel rendering is not.

---

## 8. Architecture Decisions

### ADR-001 — Disable App Sandbox
**Date:** 2026-08-10
**Decision:** `ENABLE_APP_SANDBOX = NO`; keep Hardened Runtime enabled.
**Reason:** The sandbox blocks `IOServiceOpen` on `AppleSMC` (temperature, fan speed, power
rails) without a temporary-exception entitlement Apple does not grant for App Store apps, and
constrains Accessibility-driven control of other apps' windows and enumeration of `/Applications`
for the Quick Launcher. Three of the product's core features depend on this. Every comparable
tool (Raycast, Rectangle, iStat Menus, Stats, Alfred) ships unsandboxed via Developer ID.
**Consequence:** No Mac App Store. Notarization required for distribution.
**Alternative rejected:** Sandboxed build with reduced features — would gut the product.

### ADR-002 — Swift 6 language mode with `MainActor` default isolation
**Date:** 2026-08-10
**Decision:** `SWIFT_VERSION = 6.0`, keep the template's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
and `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
**Reason:** This is a UI app; main-actor-by-default removes annotation noise while full data-race
checking still catches real bugs. It already caught two during Phase 1 (a nonisolated `deinit`
touching main-actor state, and a non-`Sendable` `UserDefaults`).
**Consequence:** Value types and protocol extensions crossing actors must be explicitly
`nonisolated`. Forgetting this on an *extension* is the common failure (see §9).

### ADR-003 — Provider-based metric architecture
**Date:** 2026-08-10
**Decision:** All metrics go through `MetricProvider` + `MetricRegistry` + `MetricSampler`.
**Reason:** Decouples system APIs from UI, makes every metric mockable, and means a new metric
appears in every surface without touching display code.
**Consequence:** One extra indirection for trivial metrics — accepted.

### ADR-004 — Provenance and unavailability are part of the data model
**Date:** 2026-08-10
**Decision:** `MetricProvenance` travels on every `MetricDescriptor`; `MetricReading` has an
explicit `.unavailable(reason)` case; `MetricValue.isPlausible` gates publication.
**Reason:** The specification's hardest requirement is not fabricating values. Enforcing it by
convention fails; enforcing it in types means a provider *cannot* publish an unlabelled or
implausible number, and the UI *cannot* forget to show a caveat.
**Consequence:** Every view must handle the unavailable case — intended.

### ADR-005 — `MetricIdentifier` is string-backed, not an enum
**Date:** 2026-08-10
**Decision:** `struct MetricIdentifier: RawRepresentable<String>`.
**Reason:** Identifiers are persisted (menu bar order, dashboard layout). An enum would make
adding a metric a breaking change for stored preferences, and force every provider to be declared
in one central file. A test asserts the wire format is the raw string, not an ordinal.
**Consequence:** Typos are not compile errors; the registry logs unknown identifiers instead.

### ADR-006 — Demand-driven sampling
**Date:** 2026-08-10
**Decision:** `MetricSampler` polls only metrics a consumer has explicitly requested and discards
values when demand is released.
**Reason:** The app runs continuously; always-on polling of IOKit is the main battery risk.
Discarding on release also removes a whole class of "stale value shown as current" bugs.
**Consequence:** Every UI must declare and release demand (`.task` / `.onDisappear`).

### ADR-007 — Swift Testing over XCTest
**Date:** 2026-08-10
**Decision:** New tests use `import Testing` (`@Suite` / `@Test` / `#expect`). XCTest boilerplate
removed.
**Reason:** First-class async and main-actor support, better parameterisation, and it is the
supported direction on Xcode 26. UI tests, if reintroduced, still require XCUITest.

---

## 9. Gotchas discovered (save future sessions the debugging)

1. **`nonisolated` must be repeated on extensions.** `nonisolated struct Foo {}` does *not* make
   `extension Foo { static let … }` nonisolated under default-MainActor isolation. Symptom:
   `main actor-isolated default value in a nonisolated context`.
2. **`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`** — every file that touches `Logger`
   needs its own `import OSLog`, even if another file in the module already imports it.
3. **Typed throws erase through existentials.** `try await (provider as any MetricProvider).read()`
   where `read()` is `throws(MetricError)` produces `any Error` at the call site. Catch with
   `catch let error as MetricError` plus an unreachable fallback.
4. **`deinit` is nonisolated** in a `@MainActor` class and cannot touch isolated state. Use an
   explicit `stopAll()`; `[weak self]` in sampling tasks makes them self-terminating anyway.
5. **A stale debug build can linger for days.** A `Barlyn` process from a previous session was
   still running and `open` merely activated it. `kill` the old pid, then `open -n`.
6. **`log show --predicate '…'` fails under this zsh** ("too many arguments") — put it in a
   `.sh` file.
7. `os_log` `.debug`/`.info` need `--info --debug` on `log show` to appear.

---

## 10. Testing strategy

Swift Testing, 33 tests, all passing. Coverage:

- Metric model: plausibility bounds (including the real `TTPD` sentinel), `checked()` downgrade,
  interval clamping, provenance, Codable round trip.
- Formatter: compact/detailed, signed wattage, em-dash placeholder, durations, paired values.
  Locale pinned to `en_US_POSIX` for determinism.
- Registry: registration, duplicate rejection (first wins), unsupported omission, stable order.
- Sampler: demand-driven activation, union across consumers, stale-value discard, failure
  surfacing, unregistered metrics inert. Polls conditions rather than sleeping fixed durations.
- Preferences: defaults, round trip through a *reopened* store, corrupt-data recovery, resets,
  stable identifier encoding.
- System providers: real `KERN_BOOTTIME` and `getloadavg` invariants (no machine-specific values).
- End-to-end: `livePipeline()` boots the real composition root and asserts formatted live values.

Rule: test *our* logic around Apple's frameworks, never Apple's frameworks.

---

## 11. Open tasks / technical debt

- [ ] **Resolve the nested git repository** (§7.3) — needs a human decision.
- [ ] `FoundationStatusView` is scaffolding; delete when Phase 4's dashboard lands.
- [ ] `PreferenceKeys.menuBarMetrics` defaults to `[.cpuUsage, .memoryUsage]`, whose providers do
      not exist until Phase 3. Inert by design, but revisit the default when they land.
- [ ] `AppInfo`/`AppConfiguration` values are English literals; move to a String Catalog before
      any localisation work.
- [ ] UI test target exists but is empty (template tests removed).
- [ ] No `.gitignore` — `xcuserdata/` is currently untracked noise.

---

## 12. Phase status

| Phase | Scope | Status |
|---|---|---|
| 1 | Foundation: lifecycle, DI, logging, config, models, protocols, preferences, tests | **Done** |
| 2 | Menu bar: `MenuBarExtra`, popover, compact metrics, configurable visibility | Next |
| 3 | System metrics: CPU, RAM, battery power, temperature | Pending |
| 4 | Dashboard: window, metric cards, widget config, graph architecture | Pending |
| 5 | Quick Launcher: global hotkey, search, action providers | Pending |
| 6 | Clipboard: monitoring, persistence, search, privacy controls | Pending |
| 7 | Window management: Accessibility, positioning, multi-display | Pending |
| 8 | Shortcut system: central manager, recorder, conflict detection | Pending |
| 9 | Onboarding | Pending |
| 10 | Polish: UX, a11y, performance, error handling | Pending |
| 11 | Future infrastructure: auth/sync/remote-config/analytics abstractions | Pending |

**Phase 2 entry notes:** switch to `MenuBarExtra` + `INFOPLIST_KEY_LSUIElement = YES` (agent app,
no Dock icon); `AppDelegate.applicationShouldTerminateAfterLastWindowClosed` must then return
`false`. Menu bar consumer uses `MetricSampler.ConsumerID.menuBar` and must release demand when
the popover closes.

---

## 13. Claude Code configuration

- **No project-level `.claude/` directory.**
- **`swiftui-pro` skill is NOT installed** and does not exist in the official marketplace
  (`~/.claude/skills/` is empty). Do not claim to be using it.
- Installed plugin: `swift-lsp@claude-plugins-official` (sourcekit-lsp at
  `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp`).
- SourceKit diagnostics reported while writing new files are usually **index lag**, not real
  errors — new files are not indexed until a build. Trust `xcodebuild`, not the live diagnostics.

---

## 14. Development workflow

PLAN → IMPLEMENT → BUILD → TEST → VERIFY → DOCUMENT → REVIEW.

A feature is done only when: it works, builds clean, tests pass, errors and permissions are
handled, the architecture stayed clean, no obvious performance regression, and **this file is
updated**.

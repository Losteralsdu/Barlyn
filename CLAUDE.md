# Barlyn — Project Knowledge Base

> Persistent knowledge for Claude Code sessions. Update this file whenever architecture,
> constraints or verified API behaviour change. Do not rely on conversation history.

---

## 1. Purpose

Barlyn is a native macOS power-user suite: menu bar system monitor, dashboard, Spotlight-like
quick launcher, clipboard history and a central global-shortcut system. **Window management is
explicitly out of scope** — see ADR-017.

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
| Bundle ID | `LSchirmer.Barlyn` |
| Signing | `DEVELOPMENT_TEAM` is blank in the project; debug builds sign ad-hoc. Set your own team locally or via `xcodebuild DEVELOPMENT_TEAM=…` — do not commit it. |
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
│   ├── Launcher/               LauncherResult, LauncherAction, provider protocol, FuzzyMatcher
│   ├── Clipboard/              ClipboardItem, ClipboardContent
│   ├── Shortcuts/              KeyCombination, ModifierKeys
│   └── Metrics/                Identifier, Unit, Value, Descriptor, Reading, Provider, Registry,
│                               Formatter, History, States
├── Infrastructure/             Cross-cutting concerns
│   ├── Configuration/          AppInfo, AppConfiguration (sampling bounds)
│   ├── Logging/                AppLog — one Logger per category
│   └── DependencyInjection/    AppEnvironment — the composition root
├── Services/                   Implementations that talk to the system
│   ├── Metrics/                MetricSampler + Providers/ + Sources/ (SMC, PowerSource)
│   ├── Launcher/               LauncherSearchService, LauncherActionRunner + Providers/
│   ├── Shortcuts/              HotkeyService (Carbon)
│   ├── Clipboard/              ClipboardService, ClipboardHistoryStorage
│   └── Preferences/            PreferenceStorage, PreferenceKey, PreferenceStore
├── Features/                   UI, one folder per feature
│   ├── MenuBar/                MenuBarConfiguration, label + panel views
│   ├── Dashboard/              DashboardConfiguration, DashboardView, MetricCard, MetricChartView
│   ├── QuickLauncher/          QuickLauncherController, Panel (NSPanel), View
│   └── Settings/               SettingsView (General, Menu Bar, Dashboard, Launcher, Clipboard)
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
        MetricRegistry (@MainActor @Observable)   ← catalogue, category-ordered
                 │
        MetricSampler (@MainActor @Observable)    ← demand-driven polling, one Task per metric
                 │
        MetricFormatter (nonisolated, locale-injected)
                 │
        Any UI: menu bar / dashboard / quick launcher
```

**Adding a metric = write a provider + append it to `AppEnvironment.bootstrap()`.**
No UI, formatter or preference change is required. Every surface — menu bar label, menu bar panel,
dashboard cards, Settings and the Quick Launcher — is written entirely against `MetricDescriptor`.
Phase 2 demonstrated this concretely: GPU temperature and fan speed were added as providers only,
and appeared everywhere with no UI edits.

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
(`setDemand(_:for: .menuBar / .menuBarPopover / .dashboard / .quickLauncher / .diagnostics)`).
Demand from all consumers is unioned; when the last consumer releases a metric its task is
cancelled **and its value discarded**, so a stale number can never be displayed.

`.menuBar` is the exception to "demand is released when UI closes": the label is visible for the
app's whole lifetime, so its demand never lapses. That makes it the only continuous energy cost in
the app, which is why the update interval is user-configurable —
`MetricSampler.setIntervalOverride(_:for:)`, applied by `MenuBarConfiguration`. All intervals,
override or not, are clamped to `AppConfiguration` bounds (floor 500 ms, ceiling 60 s), so no
persisted or hand-edited preference can poll faster than the floor.

### Dashboard and history (Phase 4)

`DashboardView` renders one `MetricCard` per visible metric in an adaptive grid.
`DashboardConfiguration` stores a **hide-list**, not a show-list — the opposite of the menu bar —
so a newly registered provider appears on the dashboard automatically. Menu bar space is scarce and
must be a chosen few; the dashboard is the full picture.

`MetricHistory` keeps a bounded in-memory window (120 samples, ~4 min at the default cadence) fed
by `MetricSampler` on every successful read, and **discarded when demand is released** — a chart
drawn across a sampling gap would imply continuity that was never measured. Nothing is written to
disk; longer retention means giving `MetricHistory` a backend and changing nothing above it.
Charts use Swift Charts (an Apple framework, not a dependency) and render nothing below two
samples, because a single point is not a trend.

### Clipboard (Phase 6)

`ClipboardService` polls `NSPasteboard.changeCount` (there is no change notification) and keeps a
bounded history behind `ClipboardHistoryStorage`. Privacy is enforced in code, not prose: entries
carrying an `org.nspasteboard.*` concealed/transient marker are skipped, contents never reach the
log at any level, the store is `0600`, and pausing tears the polling task down rather than ignoring
ticks. See ADR-015 and ADR-016.

It reaches the launcher as one more `LauncherActionProvider` returning `.copyToPasteboard`
results — the search service, ranking and UI needed no changes, which is the provider architecture
paying off a phase after it was built.

### Menu bar (Phase 2)

`MenuBarExtra` with `.menuBarExtraStyle(.window)`, plus `INFOPLIST_KEY_LSUIElement = YES` — an
agent app with no Dock icon. `MenuBarConfiguration` is the single place preferences become sampler
demand; it filters the user's chosen identifiers against what is actually registered, so a metric
whose hardware is absent is skipped rather than shown permanently broken. The dashboard `Window`
uses `.defaultLaunchBehavior(.suppressed)` so nothing appears on screen at login.

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
`host_statistics64(HOST_VM_INFO64)` confirmed. Page size **16384** on Apple Silicon.
Read it with `host_page_size()` — **not** the `vm_kernel_page_size` global, which is mutable
shared state and rejected under Swift 6 concurrency checking. Never assume 4096; doing so makes
every derived byte figure 4× too small.
`ProcessInfo.physicalMemory` = 25769803776 (24 GiB).

**"Used memory" has no single definition and tools disagree.** Measured together on this machine
(24 GiB, idle-ish):

| Definition | Result |
|---|---|
| App Memory + wired + compressed | 12.6 GiB |
| active + wired + compressed | 12.7 GiB |
| total − free − speculative (`top`'s "used") | 20.2 GiB |

`top` counts inactive as used; Activity Monitor does not. Barlyn reports the first:

```
appMemory = internal_page_count − purgeable_count   (saturating; counters sample independently)
used      = appMemory + wire_count + compressor_page_count
```

`internal` rather than `active`, because inactive *anonymous* pages are still app memory.
File-backed (`external`) pages are excluded — cache, not usage.
**Open: this has not been compared side by side with Activity Monitor's UI.** The composition
follows Apple's description and is self-consistent, but a human should confirm it once.

### Battery power — **available and reliable** (implemented, Phase 3)
Live cross-check of the running app against `ioreg` at the same moment: app reported
`+9.4 W` system input vs `SystemPowerIn = 9358` mW, and `12.45 V` vs `Voltage = 12452` mV. Exact.

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

### CPU temperature — **available via SMC, with real caveats** (implemented, Phase 3)
`IOServiceOpen` on `AppleSMC` **succeeded** from an unsandboxed process. 3485 keys enumerated;
**67 classified as usable sensors**, of which **23 are `Tp…` P-core die sensors**.
Live app readings: mean **49 °C**, peak 53 °C — consistent with the standalone probe.
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
5. **Measured discovery cost: ~480 ms** in the real app (~3500 `kSMCGetKeyFromIndex` calls plus
   `kSMCGetKeyInfo` for matches). Done once per process and cached in `SMCService`; only the
   selected sensors are re-read per sample. Because 480 ms is too long to sit on the launch path,
   `AppEnvironment.bootstrap()` registers SMC-backed providers in a **second wave** (ADR-008).
   In test runs several `SMCService` instances contend and report ~2.6 s — that is contention,
   not the real single-process cost.
   *Possible future optimisation:* observed key order is alphabetical, so the `Tp…` range could be
   binary-searched instead of fully enumerated. Not done — it would make correctness depend on an
   undocumented ordering guarantee for a 480 ms one-off saving.

Public alternative, always available, no caveats: `ProcessInfo.thermalState`
(nominal/fair/serious/critical) — verified working. Ship this as the guaranteed baseline.

### Misc verified
- `sysctl KERN_BOOTTIME` = wall-clock uptime (matches `uptime(1)`).
  `ProcessInfo.systemUptime` is `mach_absolute_time`-based and **does not advance during sleep** —
  it is "awake time", not uptime. `UptimeMetricProvider` uses `KERN_BOOTTIME`.
- `ProcessInfo.isLowPowerModeEnabled`, `activeProcessorCount` — fine.

### Global hotkeys — **verified working** (implemented, Phase 5)
Carbon `RegisterEventHotKey` on macOS 26 / Apple Silicon, unsandboxed, **no permission required**:

| Case | Result |
|---|---|
| `Option+Space` | `noErr` — works |
| Same combination twice in one process | `eventHotKeyExistsErr` (−9878) |
| Same combination from a *different* process | `noErr` — cross-process duplicates are allowed |
| `Command+Space` (Spotlight owns it) | **`noErr`** — then silently never fires |
| `InstallEventHandler` on the dispatcher target | `noErr` |

**The critical gap:** registering a combination macOS or another app already owns *succeeds*, and
the key press then never arrives because the other handler wins. Carbon offers no way to detect
this. Conflict detection is therefore only reliable *within* Barlyn, and the UI must never claim a
shortcut works merely because registration returned `noErr` — Settings says so explicitly.

`NSEvent.addGlobalMonitorForEvents` is not a substitute: it needs Input Monitoring **and** cannot
consume the event, so the launcher shortcut would also type into the focused app.

### Applications on disk (implemented, Phase 5)
**Finder is not in `/System/Applications`** — it lives in `/System/Library/CoreServices`, which
also holds ~117 background agents. Filtering on `LSUIElement` / `LSBackgroundOnly` in each app's
`Info.plist` is the same rule macOS uses to keep an app out of the Dock, so it needs no
hand-maintained blocklist. Result on this machine: **130 launchable apps indexed in 20 ms**, cached
for 5 minutes. Barlyn excludes itself, correctly, being `LSUIElement`.

### Clipboard — **verified** (implemented, Phase 6)
There is **no pasteboard-change notification**; `NSPasteboard.changeCount` polling is the only
option. Measured on this machine: **0.73 µs per `changeCount` read** (20,000 reads in 14.6 ms), so
the poll interval is a responsiveness decision, not an energy one. Default 0.5 s.

| Finding | Detail |
|---|---|
| Our own write | Increments `changeCount` by exactly **1** — self-capture is suppressible by recording the expected count |
| `org.nspasteboard.ConcealedType` | Detectable via `data(forType:)`; this is how password managers opt out |
| **A URL-only item has no `.string` type** | `string(forType: .string)` returns **nil** for a copied URL — a text-only monitor silently misses every link. Read `readObjects(forClasses: [NSURL.self])` first |
| Source application | Not exposed by macOS. `frontmostApplication` at capture time is a *heuristic* and is labelled as such in the model |

End-to-end verified in the running app: a copied string and a copied URL were stored as `.text`
and `.url` respectively, the history file is `-rw-------`, and the marker string appeared **0
times** in Barlyn's log and 0 times in the system-wide log.

### No longer relevant
Accessibility `AXUIElement` window control and `NSScreen` multi-display geometry were the open
investigations for Phase 7. Both are dropped with it (ADR-017) and were never probed.

---

## 6. Permissions

**Barlyn currently requires no permissions at all.** Accessibility was needed only by window
management, which is dropped (ADR-017); Carbon hotkeys need nothing; metrics, SMC and clipboard
need nothing beyond running unsandboxed.

| Permission | Needed for | Status |
|---|---|---|
| — | Metrics, SMC, clipboard, global hotkeys, app launching | **None required** |
| Accessibility | Nothing, since window management was dropped | Not requested |
| Input Monitoring | Nothing — Carbon hotkeys avoid it entirely | Not requested |

The `PermissionManager` §30 asks for is therefore **not built**: there is no permission to manage,
and an abstraction over an empty set is the kind of speculative structure §49 warns against.
`PermissionKind` remains in `Core/Errors/BarlynError.swift` as a small, already-written extension
point should a future feature need one.

This is worth stating as a product property: Barlyn asks for nothing, which is unusual for a Mac
utility in this category and is a direct consequence of dropping window management.

---

## 7. Known limitations & risks

1. **No Mac App Store distribution** — consequence of disabling the sandbox (ADR-001).
   Distribution is Developer ID + notarization.
2. **SMC sensor naming is inferred**, not documented; may differ on other Macs and may break on
   future chips. Mitigation: runtime discovery, range checks, `MetricProvenance` in the UI.
3. ~~Nested git repository~~ **Resolved 2026-08-26.** `Barlyn/` (the source folder) had its own
   `.git` tracking only that subfolder — a clone of it could not build, having no `.xcodeproj` and
   no tests. It was fully pushed, so it was removed and the project-root repo (which has the real
   history) took over its GitHub remote. `README.md` and `.gitattributes` moved to the project
   root, out of the synchronized group, so `README.md` is no longer copied into the app bundle.
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

### ADR-008 — Two-wave provider registration
**Date:** 2026-08-14
**Decision:** `AppEnvironment.bootstrap()` registers providers with cheap support checks
synchronously, then registers hardware-probed providers (currently CPU temperature) from a
background `Task`. `awaitFullRegistration()` exists for tests.
**Reason:** SMC key discovery measures ~480 ms. Blocking launch on it means the window renders
empty for half a second on every start of an app intended to launch at login. `MetricRegistry`
is `@Observable`, so late arrivals appear without any UI coordination.
**Consequence:** `descriptors` order is arrival order, so CPU temperature currently sorts last.
Acceptable while the default order is provisional; Phase 2/4 persist a user-defined order anyway.
A test asserts `bootstrap()` returns in under 250 ms.

### ADR-009 — Battery power and system input power are separate metrics
**Date:** 2026-08-14
**Decision:** Ship `battery.power` (signed, battery-side, `Amperage × Voltage`) and
`power.systemInput` (adapter draw, `PowerTelemetryData.SystemPowerIn`) as two distinct metrics.
**Reason:** They are different physical quantities that users conflate. On AC with a charged
battery they read 0 W and ~9 W respectively; presenting either as "power consumption" would be
wrong half the time.
**Consequence:** Two rows where other tools show one. On battery, `power.systemInput` reports
*unavailable* rather than 0 W — there is no adapter draw to measure, which is not the same
statement as "the Mac is using no power".

### ADR-010 — Menu bar demand is permanent; the interval is the user's energy control
**Date:** 2026-08-26
**Decision:** `ConsumerID.menuBar` holds sampler demand for the app's entire lifetime rather than
acquiring and releasing it like every other consumer. The menu bar panel uses a separate
`.menuBarPopover` consumer that releases on close.
**Reason:** The menu bar label is always visible, so its metrics must always be current — there is
no "closed" state to release on. That makes it the app's only continuous polling cost, so it gets
an explicit user-facing update interval instead of a hidden default.
**Consequence:** Barlyn always samples something while running. The floor in `AppConfiguration`
caps the worst case, and users who want zero background polling can deselect every menu bar metric,
which leaves the label as a static icon and demand genuinely empty.

### ADR-011 — The dashboard stores a hide-list; the menu bar stores a show-list
**Date:** 2026-08-26
**Decision:** `dashboard.hiddenMetrics` records what the user has switched *off*, while
`menuBar.metrics` records what they switched *on*.
**Reason:** They answer different questions. Menu bar width is shared with every other app, so its
contents must be a deliberate few and an opt-in list is correct. The dashboard is the full picture,
and a metric added by a later version should appear there without the user having to discover and
enable it — which an opt-in list would prevent.
**Consequence:** Two shapes of configuration for what looks like one problem. The asymmetry is
deliberate and is what keeps "add a provider, it shows up everywhere" true after Phase 4.

### ADR-012 — Metric history is in-memory, bounded, and dropped with demand
**Date:** 2026-08-26
**Decision:** `MetricHistory` keeps 120 samples per metric in memory, records only available
readings, and clears a metric's series when its sampling stops.
**Reason:** The MVP needs live values with room for history later, not a time-series database.
Dropping on release follows ADR-006: a chart that spans a period when nothing was sampled draws a
continuous line through data that was never collected, which is the visual form of fabricating a
value.
**Consequence:** Opening the dashboard shows charts that fill in over the following seconds rather
than instantly. Menu bar metrics are the exception — they sample continuously, so their history is
already populated. Persistent history means giving `MetricHistory` a storage backend; no consumer
changes.

### ADR-013 — Carbon `RegisterEventHotKey` for global shortcuts
**Date:** 2026-08-26
**Decision:** Global hotkeys go through Carbon, wrapped in `HotkeyService`.
**Reason:** It is the only mechanism that needs **no permission** and **consumes** the keystroke.
`NSEvent.addGlobalMonitorForEvents` requires Input Monitoring and cannot stop the event reaching
the focused app, so pressing the launcher shortcut would also type into whatever was open.
Verified working on macOS 26 / Apple Silicon.
**Consequence:** A deprecated-looking API in the codebase, isolated behind one service. Conflict
detection is partial: same-process collisions are caught, system-owned ones are undetectable, and
the UI states that limitation rather than implying the shortcut is guaranteed.

### ADR-014 — Launcher actions are an enum, not closures
**Date:** 2026-08-26
**Decision:** `LauncherResult.action` is a `LauncherAction` enum; `LauncherActionRunner` is the one
place it becomes a side effect.
**Reason:** Closures would make results non-`Sendable`, capture UI state, and scatter side effects
across every provider. An enum keeps results comparable value types that can be ranked, cached and
asserted on in tests, and puts every externally visible thing the launcher can do in one auditable
file.
**Consequence:** Adding a new kind of action means adding a case and handling it in the runner,
rather than a provider inventing its own behaviour — which is the point.

### ADR-015 — Clipboard privacy is enforced in code, not documented in prose
**Date:** 2026-08-27
**Decision:** `ClipboardService` skips any pasteboard entry carrying an `org.nspasteboard.*`
concealed/transient marker, never logs contents at any level, stores history `0600`, and tears the
polling task down when paused rather than merely ignoring ticks. Tests assert each of these.
**Reason:** §21 and §37 are the strictest requirements in the specification, and "we are careful"
is not a mechanism. Honouring the platform's existing opt-out marker also avoids a hand-maintained
list of password-manager bundle ids that would rot immediately.
**Consequence:** Entries from apps that set the marker are invisible to Barlyn, by design and with
no user-facing setting to override it.

### ADR-016 — Clipboard history is stored unencrypted, and that is recorded as debt
**Date:** 2026-08-27
**Decision:** History is a JSON file in Application Support with `0600` permissions, not encrypted.
**Reason:** Encryption needs a key, and the only sensible home for one is the Keychain, which
belongs with the credential work in Phase 11. Inventing a bespoke key store here would be worse
than waiting.
**Consequence:** The most sensitive thing Barlyn stores is readable by anything running as the
user. Settings says so in plain language rather than implying the history is protected, and it is
tracked as an open task.

### ADR-017 — Window management is out of scope
**Date:** 2026-08-27
**Decision:** Drop Phase 7 entirely. Barlyn does not move, resize or snap other apps' windows.
**Reason:** Product decision by the owner — window management will live in a separate application.
**Consequences, which reach further than one phase:**
- **Barlyn now requires no permissions at all.** Accessibility was needed only by this feature, so
  the `PermissionManager` §30 asks for is not built: there is nothing to manage, and an abstraction
  over an empty set is speculative structure.
- `AXUIElement` and `NSScreen` multi-display geometry were never probed and are now moot.
- **ADR-001 still stands.** The sandbox remains disabled because `IOServiceOpen` on `AppleSMC`
  (temperature, fan, power rails) and `/Applications` enumeration both require it. Window
  management was one of three justifications, not the only one, so Mac App Store distribution does
  not become available.
- Phase 8 shrinks: the `window.move*` shortcuts §28 lists no longer exist, leaving a handful of
  app-level shortcuts and making a heavyweight central manager unwarranted.
- Phase 9 shrinks: the onboarding permission step disappears.

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
8. **`print()` from tests does not reach `xcodebuild` stdout.** To capture live values from a test,
   write to a file instead.
9. **`vm_kernel_page_size` is a mutable global** and fails Swift 6 concurrency checking. Use
   `host_page_size(mach_host_self(), &size)`.
10. **`Duration` has no `.milliseconds` accessor** — destructure `components` (seconds,
    attoseconds). A small extension lives in `SMCService.swift`.
11. **`CGWindowListCopyWindowInfo` does not report another process's menu bar status item** on
    macOS 26, and reports no windows at all for an accessory app with nothing open. It is not a
    usable oracle for "did the `MenuBarExtra` appear". To verify that, log from the label view's
    `body` and read the log — a repeatedly-evaluated body is the status item live-updating.
12. **A `MenuBarExtra` label is not a dependable place for one-time lifecycle work.** Bootstrapping
    is kicked off from `BarlynApp.init` instead, because the panel may never be opened.
13. **Swift 6.3.3 miscompiles `dict[key]?.member` when the value struct starts with a non-nullable
    pointer.** `HotkeyService.Registration` begins with an `EventHotKeyRef`, which `Optional` uses
    as its extra-inhabitant tag. On an *empty* dictionary, `registrations[id]?.combination`
    returned a non-nil value full of raw memory while `registrations[id] == nil` evaluated to
    `true` **in the same function** — reproduced deliberately, twice, in Debug/-Onone. The explicit
    `guard let … else { return nil }` form is correct. `combination(for:)` carries a comment saying
    so; do not "simplify" it back.
14. **Swift Testing runs tests in parallel, which breaks anything using process-wide OS state.**
    Global hotkey registrations are shared across the whole process, so `HotkeyServiceTests` is
    marked `.serialized` and each test uses a distinct key. Symptom without it: registrations
    colliding non-deterministically between unrelated tests.
15. **`xcrun xcresulttool` will not readily surface a Swift Testing failure message.** The fastest
    route to a real diagnosis is a temporary test that writes its findings to a file (see also
    gotcha 8).
16. **A URL on the pasteboard has no `.string` representation.** `string(forType: .string)` returns
    nil for an item written as a URL, so URL reading must come first. Verified with a probe.
17. **Never test against `NSPasteboard.general`.** It would read and clobber whatever the developer
    has copied. `ClipboardTests` creates a uniquely-named private pasteboard per test.
18. **`Mutex<Void>` closures still take a parameter** — `lock.withLock { _ in … }`, not
    `lock.withLock { … }`.

---

## 10. Testing strategy

Swift Testing, 125 tests, all passing. Coverage:

**Phase 6 clipboard** (all against a private `NSPasteboard`, never `.general`):
- Privacy: concealed/transient/auto-generated markers suppress recording entirely; pausing stops
  capture and resuming does **not** backfill what was copied during the pause; clearing wipes
  memory and storage.
- Capture: text and URLs both recorded (a URL-only item has no `.string` type); a link copied as
  plain text is still recognised as a URL; re-copying moves an entry to the top instead of
  duplicating; an unchanged pasteboard is not re-recorded.
- Limits: history is capped oldest-first, and lowering the limit trims immediately.
- Restoring an entry writes it back without re-capturing it as a new copy.
- Launcher: entries become `.copyToPasteboard` results; a blank launcher offers only a few recent
  entries and ranks them below metrics and commands.

**Phase 5 quick launcher:**
- Fuzzy matching tiers: exact > prefix > word-boundary > contains > subsequence; shorter
  candidates win ties; non-matches return `nil` rather than a low score; case-insensitive both ways.
- Ranking puts relevance above section, so a strong app match beats a weak metric match; section
  breaks ties; results are capped.
- Commands match aliases ("preferences" finds Settings), metric rows carry `.none` and are
  informational, applications return nothing for an empty query.
- Real hardware: Finder is discoverable (it lives in CoreServices, not `/System/Applications`) and
  background agents are excluded.
- Pipeline: a live query flows through all providers concurrently and ranks; a newer query cancels
  an older one so stale results cannot overwrite fresher ones.
- Key combinations: canonical modifier order (⌃⌥⇧⌘), Carbon bit mapping, modifier-less rejection,
  Codable round trip.
- `HotkeyService` (`.serialized` — hotkeys are process-wide): re-registering an id replaces rather
  than collides, and a combination already held inside Barlyn is refused.

**Phase 4 dashboard:**
- History records only real measurements — unavailable readings never become zeroes.
- The window is bounded and slides forward (oldest dropped, not newest).
- Clearing is scoped to one metric; releasing demand discards that metric's history.
- Everything registered is visible by default; a metric registered *after* the user has reordered
  still appears, and does not displace their arrangement.
- Hiding is idempotent, reordering clamps at both ends, reset restores defaults.
- Layout and chart preference survive a reopened store.

**Phase 2 menu bar:**
- Preferences naming unregistered metrics are filtered out, not rendered broken.
- Visible order follows the user's order, not registration order.
- Toggling visibility adds and removes sampler demand; adding twice does not duplicate.
- Reordering clamps at both ends instead of wrapping.
- The update interval reaches the sampler and is clamped to the configured floor.
- Descriptors sort by category regardless of which registration wave they arrived in.

**Phase 3 providers** (real hardware; assertions are on invariants, never machine-specific values):
- CPU: first sample must report `notYetSampled` (never usage-since-boot); `100 − idle` agrees with
  the headline; the four states sum to ~100 %; repeated sampling stays in range.
- Memory: `used == app + wired + compressed`; percentage agrees; App Memory cannot underflow;
  cached files excluded from used; page size read from the kernel.
- SMC: `SMCKeyData` stride is exactly 80 bytes; discovered keys match their family prefix; every
  surviving temperature is plausible; fan keys are `…Ac` actuals, not `Mn`/`Mx`/`Tg` limits.
- Power: watts derive from amperage × voltage with the signed convention; battery state
  distinguishes plugged-in-not-charging from full; system power is *unavailable* on battery,
  not 0 W; the snapshot is cached rather than re-read per provider.
- Bootstrap returns in < 250 ms despite the ~480 ms SMC probe.

**Phase 1 foundation:**

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

- [ ] **Confirm the memory "used" figure against Activity Monitor's UI** (§5). Composition follows
      Apple's description and is self-consistent, but has not been eyeballed side by side.
- [ ] Metric history is in-memory only and capped at 120 samples (~4 min at the default cadence).
      Longer ranges need a storage backend behind `MetricHistory`; nothing above it would change.
- [ ] `MetricCard` shows at most four components; the full breakdown has no detail view yet.
- [ ] `AppInfo`/`AppConfiguration` values are English literals; move to a String Catalog before
      any localisation work.
- [ ] UI test target exists but is empty (template tests removed).
- [ ] The launcher shortcut is fixed at ⌥Space until Phase 8 adds the recorder; Settings shows it
      read-only.
- [ ] Only the launcher shortcut exists. With window management dropped (ADR-017) the remaining
      candidates are: open dashboard, toggle clipboard recording, open launcher scoped to clipboard.
- [ ] `ApplicationActionProvider` refreshes on a 5-minute TTL rather than watching for installs.
- [ ] **Clipboard history is not encrypted at rest** (ADR-016). Needs a Keychain-held key; revisit
      with Phase 11's credential work.
- [ ] Clipboard supports text and URLs only. Images, files and rich text are modelled for
      (`ClipboardContent` is an enum) but not implemented; large payloads should go to files on
      disk referenced by id rather than inline in the JSON.
- [ ] The per-app ignore list §21 asks for is designed for (`sourceBundleIdentifier` is captured)
      but has no UI. Note the field is a frontmost-app heuristic, not the true owner.

---

## 12. Phase status

| Phase | Scope | Status |
|---|---|---|
| 1 | Foundation: lifecycle, DI, logging, config, models, protocols, preferences, tests | **Done** |
| 2 | Menu bar: `MenuBarExtra`, panel, compact metrics, configurable visibility | **Done** |
| 3 | System metrics: CPU, RAM, battery power, temperature | **Done** |
| 4 | Dashboard: window, metric cards, widget config, graph architecture | **Done** |
| 5 | Quick Launcher: global hotkey, search, action providers | **Done** |
| 6 | Clipboard: monitoring, persistence, search, privacy controls | **Done** |
| 7 | ~~Window management~~ | **Dropped** (ADR-017) |
| 8 | Shortcut system: recorder, customisable shortcuts, conflict detection | Next |
| 9 | Onboarding | Pending |
| 10 | Polish: UX, a11y, performance, error handling | Pending |
| 11 | Future infrastructure: auth/sync/remote-config/analytics abstractions | Pending |

**Phase 8 entry notes:** the substance is the **shortcut recorder**, which Settings currently
promises and does not have. `HotkeyService` already handles registration, replacement and
same-process conflict detection; what is missing is a SwiftUI recorder view that captures a key
combination (an `NSView` capturing `keyDown` plus `flagsChanged`, since SwiftUI has no recorder),
plus persistence per shortcut id.

Do **not** build a heavyweight central manager. With window management dropped there are only a
few shortcut actions worth having — toggle the launcher, open the dashboard, pause clipboard
recording — and a registry over three entries is the speculative structure §49 warns against.
Extend `PreferenceKeys` with one key per shortcut and let `HotkeyService` stay the single owner.

The honesty constraint is already established and must survive into the recorder UI: Carbon
reports registering a *system-owned* combination as success, and the key press then never arrives.
The recorder must not imply a shortcut works merely because it was accepted.

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

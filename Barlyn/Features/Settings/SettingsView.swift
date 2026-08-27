import SwiftUI

/// Settings window.
///
/// Sections mirror the app's feature areas so the shape stays recognisable as later phases add
/// Quick Launcher, Clipboard, Window Management and Shortcuts tabs.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            MenuBarSettingsView()
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            DashboardSettingsView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            LauncherSettingsView()
                .tabItem { Label("Quick Launcher", systemImage: "magnifyingglass") }
            ClipboardSettingsView()
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
        }
        .frame(width: 460)
    }
}

struct GeneralSettingsView: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        Form {
            Picker("Appearance", selection: appearanceBinding) {
                ForEach(AppearancePreference.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Section {
                LabeledContent("Version", value: AppInfo.versionDescription)
                Button("Reset All Settings…", role: .destructive) {
                    environment.preferences.resetAll()
                    environment.menuBarConfiguration.apply()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 220)
    }

    private var appearanceBinding: Binding<AppearancePreference> {
        Binding(
            get: { environment.preferences[PreferenceKeys.appearance] },
            set: { environment.preferences[PreferenceKeys.appearance] = $0 }
        )
    }
}

/// Chooses which metrics appear in the menu bar, in what order, and how often they refresh.
struct MenuBarSettingsView: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        Form {
            Section("Visible in Menu Bar") {
                let visible = environment.menuBarConfiguration.visibleMetrics
                if visible.isEmpty {
                    Text("No metrics selected. The menu bar shows the Barlyn icon.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, descriptor in
                        HStack {
                            Label(descriptor.displayName, systemImage: descriptor.symbolName)
                            Spacer()
                            // Explicit move buttons rather than drag-only reordering, so the
                            // order is reachable by keyboard and VoiceOver.
                            Button {
                                environment.menuBarConfiguration.move(descriptor.id, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(index == 0)
                            .accessibilityLabel("Move \(descriptor.displayName) earlier")

                            Button {
                                environment.menuBarConfiguration.move(descriptor.id, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(index == visible.count - 1)
                            .accessibilityLabel("Move \(descriptor.displayName) later")

                            Button {
                                environment.menuBarConfiguration.setVisible(false, for: descriptor.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .accessibilityLabel("Remove \(descriptor.displayName)")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section("Available") {
                let hidden = environment.metricRegistry.descriptors.filter {
                    !environment.menuBarConfiguration.isVisible($0.id)
                }
                if hidden.isEmpty {
                    Text("Every available metric is already shown.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hidden) { descriptor in
                        HStack {
                            Label(descriptor.displayName, systemImage: descriptor.symbolName)
                            if let caveat = descriptor.provenance.caveatText {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.tertiary)
                                    .help(caveat)
                            }
                            Spacer()
                            Button {
                                environment.menuBarConfiguration.setVisible(true, for: descriptor.id)
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Add \(descriptor.displayName)")
                        }
                    }
                }
            }

            Section("Display") {
                Picker("Style", selection: styleBinding) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                // The menu bar samples continuously for the whole life of the app, so this
                // slider is a direct energy control, not a cosmetic one. The bounds come from
                // AppConfiguration rather than being written here twice.
                LabeledContent("Update Interval") {
                    HStack {
                        Slider(
                            value: intervalBinding,
                            in: Self.intervalBounds,
                            step: 0.5
                        )
                        Text("\(intervalBinding.wrappedValue, format: .number.precision(.fractionLength(1)))s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 380)
    }

    private static let intervalBounds: ClosedRange<Double> = {
        let low = Double(AppConfiguration.minimumSampleInterval.components.seconds)
            + Double(AppConfiguration.minimumSampleInterval.components.attoseconds) / 1e18
        return low...10
    }()

    private var styleBinding: Binding<MenuBarStyle> {
        Binding(
            get: { environment.preferences[PreferenceKeys.menuBarStyle] },
            set: { environment.menuBarConfiguration.setStyle($0) }
        )
    }

    private var intervalBinding: Binding<Double> {
        Binding(
            get: { environment.preferences[PreferenceKeys.menuBarUpdateInterval] },
            set: { environment.menuBarConfiguration.setUpdateInterval($0) }
        )
    }
}

/// Chooses which metric cards the dashboard shows, in what order, and whether cards chart.
struct DashboardSettingsView: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        Form {
            Section("Cards") {
                let visible = environment.dashboardConfiguration.visibleMetrics
                if visible.isEmpty {
                    Text("Every metric is hidden.").foregroundStyle(.secondary)
                }
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, descriptor in
                    HStack {
                        Label(descriptor.displayName, systemImage: descriptor.symbolName)
                        Spacer()
                        Button {
                            environment.dashboardConfiguration.move(descriptor.id, by: -1)
                        } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                            .accessibilityLabel("Move \(descriptor.displayName) earlier")
                        Button {
                            environment.dashboardConfiguration.move(descriptor.id, by: 1)
                        } label: { Image(systemName: "chevron.down") }
                            .disabled(index == visible.count - 1)
                            .accessibilityLabel("Move \(descriptor.displayName) later")
                        Button {
                            environment.dashboardConfiguration.setVisible(false, for: descriptor.id)
                        } label: { Image(systemName: "eye.slash") }
                            .accessibilityLabel("Hide \(descriptor.displayName)")
                    }
                    .buttonStyle(.borderless)
                }
            }

            let hidden = environment.dashboardConfiguration.hiddenMetrics
            if !hidden.isEmpty {
                Section("Hidden") {
                    ForEach(hidden) { descriptor in
                        HStack {
                            Label(descriptor.displayName, systemImage: descriptor.symbolName)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                environment.dashboardConfiguration.setVisible(true, for: descriptor.id)
                            } label: { Image(systemName: "eye") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Show \(descriptor.displayName)")
                        }
                    }
                }
            }

            Section("Display") {
                Toggle("Show trend charts", isOn: chartsBinding)
                Button("Reset Layout") { environment.dashboardConfiguration.resetLayout() }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 380)
    }

    private var chartsBinding: Binding<Bool> {
        Binding(
            get: { environment.dashboardConfiguration.showsCharts },
            set: { environment.dashboardConfiguration.setShowsCharts($0) }
        )
    }
}

/// Quick Launcher settings.
///
/// The shortcut is displayed but not yet re-recordable: a proper recorder, with conflict
/// detection, is Phase 8's job and belongs to the central shortcut system rather than being
/// built once here and again later.
struct LauncherSettingsView: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        Form {
            Section("Shortcut") {
                Toggle("Enable Quick Launcher", isOn: enabledBinding)

                LabeledContent("Shortcut") {
                    Text(environment.preferences[PreferenceKeys.launcherHotkey].displayString)
                        .font(.title3.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .rect(cornerRadius: 5))
                }

                Text("Customising the shortcut arrives with the shortcut recorder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                // Stated plainly because macOS gives no way to detect it: Carbon reports
                // registering a system-owned combination as a success, and the key press then
                // never arrives. Claiming otherwise would be a promise the app cannot keep.
                Label(
                    "If another app or macOS already owns this combination, that app wins and Barlyn never receives the key press. macOS provides no way to detect this, so try the shortcut after changing it.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 260)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { environment.preferences[PreferenceKeys.launcherEnabled] },
            set: {
                environment.preferences[PreferenceKeys.launcherEnabled] = $0
                environment.applyLauncherHotkey()
            }
        )
    }
}

/// Clipboard history settings, including the privacy controls §21 requires.
struct ClipboardSettingsView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section("Recording") {
                Toggle("Record clipboard history", isOn: enabledBinding)
                LabeledContent("Status") {
                    Label(
                        environment.clipboard.isMonitoring ? "Recording" : "Paused",
                        systemImage: environment.clipboard.isMonitoring ? "record.circle" : "pause.circle"
                    )
                    .foregroundStyle(environment.clipboard.isMonitoring ? .green : .secondary)
                }

                Stepper(
                    "Keep \(environment.clipboard.historyLimit) entries",
                    value: limitBinding,
                    in: 10...500,
                    step: 10
                )
            }

            Section("History") {
                LabeledContent("Stored entries", value: "\(environment.clipboard.items.count)")
                Button("Clear History…", role: .destructive) { isConfirmingClear = true }
                    .disabled(environment.clipboard.items.isEmpty)
            }

            Section("Privacy") {
                // These are statements of fact about the implementation, not reassurance:
                // each corresponds to something enforced in ClipboardService.
                privacyRow("Everything stays on this Mac — no sync, no network", "lock.laptopcomputer")
                privacyRow("Clipboard contents are never written to the log", "eye.slash")
                privacyRow("Entries marked private by their app are skipped entirely", "hand.raised")
                privacyRow("History is stored owner-only, but is not yet encrypted at rest", "exclamationmark.triangle")
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 420)
        .confirmationDialog(
            "Clear clipboard history?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear \(environment.clipboard.items.count) Entries", role: .destructive) {
                environment.clipboard.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every stored entry from this Mac. It cannot be undone.")
        }
    }

    private func privacyRow(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { environment.preferences[PreferenceKeys.clipboardEnabled] },
            set: {
                environment.preferences[PreferenceKeys.clipboardEnabled] = $0
                environment.clipboard.applyMonitoringPreference()
            }
        )
    }

    private var limitBinding: Binding<Int> {
        Binding(
            get: { environment.clipboard.historyLimit },
            set: {
                environment.preferences[PreferenceKeys.clipboardHistoryLimit] = $0
                environment.clipboard.applyHistoryLimit()
            }
        )
    }
}

#Preview {
    SettingsView()
        .environment(\.appEnvironment, .ephemeral())
}

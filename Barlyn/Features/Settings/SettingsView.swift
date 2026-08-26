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

#Preview {
    SettingsView()
        .environment(\.appEnvironment, .ephemeral())
}

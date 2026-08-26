import AppKit
import SwiftUI

/// The launcher's contents: a search field over a ranked result list.
///
/// Keyboard-first by construction. Every action is reachable without the mouse: type to search,
/// arrows to move, Return to run, Escape to dismiss.
struct QuickLauncherView: View {
    @Environment(\.appEnvironment) private var environment

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let controller = environment.quickLauncher

        VStack(spacing: 0) {
            searchField(controller)
            if !controller.results.isEmpty {
                Divider()
                resultList(controller)
            }
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .onAppear { isSearchFocused = true }
    }

    private func searchField(_ controller: QuickLauncherController) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.title3)

            TextField("Search", text: searchBinding(controller))
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($isSearchFocused)
                .onSubmit { controller.runSelected() }
                // Arrow keys are intercepted on the field itself: attached to an ancestor they
                // would never fire, because the focused text field consumes them first.
                .onKeyPress(.upArrow) { controller.moveSelection(by: -1); return .handled }
                .onKeyPress(.downArrow) { controller.moveSelection(by: 1); return .handled }
                .onKeyPress(.escape) { controller.hide(); return .handled }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func resultList(_ controller: QuickLauncherController) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(controller.results.enumerated()), id: \.element.id) { index, result in
                        LauncherRow(result: result, isSelected: index == controller.selectedIndex)
                            .id(result.id)
                            .contentShape(.rect)
                            .onTapGesture { controller.run(result) }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 320)
            .onChange(of: controller.selectedIndex) { _, index in
                // Keyboard navigation must drag the viewport along with it, or the selection
                // walks off screen and the user is steering blind.
                guard controller.results.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(controller.results[index].id, anchor: .center)
                }
            }
        }
    }

    private func searchBinding(_ controller: QuickLauncherController) -> Binding<String> {
        Binding(
            get: { controller.queryText },
            set: { controller.updateQuery($0) }
        )
    }
}

private struct LauncherRow: View {
    let result: LauncherResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .lineLimit(1)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(result.kind.displayName)
                .font(.caption2)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.tertiary))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.title)
        .accessibilityValue(result.subtitle ?? result.kind.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var icon: some View {
        if let path = result.iconPath {
            // The real application icon, which is far more scannable than a generic glyph.
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: result.symbolName)
                .font(.title3)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
    }
}

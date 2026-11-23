import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    private var palette: FocusPalette { FocusPalette(phase: state.timer.phase, dark: scheme == .dark, style: state.visualStyle) }
    var body: some View {
        Form {
            Section(state.text("appearance")) {
                Picker(state.text("visualStyle"), selection: $state.visualStyle) {
                    ForEach(VisualStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }.pickerStyle(.segmented)
                ThemeSwatches(state: state)
                Picker(state.text("language"), selection: $state.language) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                Toggle(state.text("dayPlan"), isOn: $state.showPlan)
            }
            Section(state.text("timerSettings")) {
                Toggle(state.text("autoAdvance"), isOn: $state.autoAdvance)
                Text(state.text("autoAdvanceDetail")).font(.caption).foregroundStyle(.secondary)
                Toggle(state.text("transitionSounds"), isOn: $state.soundEnabled)
                HStack {
                    Button(state.text("previewWorkSound")) { state.previewTransitionSound(for: .focus) }
                    Button(state.text("previewBreakSound")) { state.previewTransitionSound(for: .shortBreak) }
                }
            }
            Section(state.text("updates")) {
                UpdateCheckButton(state: state, updates: state.updates)
                Text(state.text("updatesDetail")).font(.caption).foregroundStyle(.secondary)
            }
            Section(state.text("controls")) {
                LabeledContent(state.text("navigation"), value: "⌘1 – ⌘5")
                LabeledContent(state.text("miniTimer"), value: "⇧⌘M")
                LabeledContent(state.text("togglePlan"), value: "⇧⌘P")
                LabeledContent(state.text("startPause"), value: "⇧⌘S")
            }
            Section {
                Text(state.text("sleepPolicy")).foregroundStyle(.secondary)
                Text(state.text("prototypeNotice")).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).scrollContentBackground(state.visualStyle == .classic ? .visible : .hidden).background(palette.background)
    }
}

struct UpdateCheckButton: View {
    @ObservedObject var state: AppState
    @ObservedObject var updates: UpdateController

    var body: some View {
        Button(state.text("checkForUpdates")) { updates.checkForUpdates() }
            .disabled(!updates.canCheckForUpdates && updates.availableVersion == nil)
    }
}

private struct ThemeSwatches: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 12) {
            ForEach([Theme.light, .dark], id: \.self) { theme in
                let dark = theme == .dark
                let palette = FocusPalette(phase: .focus, dark: dark, style: state.visualStyle)
                let selected = state.theme == theme || (state.theme == .system && (scheme == .dark) == dark)
                Button { state.theme = theme } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 5).fill(palette.accent).frame(width: 20, height: 20)
                        Text(state.visualStyle.title + " · " + state.text(theme.rawValue))
                            .font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 2)
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                            .opacity(selected ? 1 : 0)
                    }
                    .foregroundStyle(palette.ink).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? palette.accent.opacity(0.65) : palette.border, lineWidth: selected ? 1.5 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(FocusPressStyle())
                .help(state.text(theme.rawValue))
                .accessibilityLabel(state.text(theme.rawValue))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .contextMenu {
                    Button { state.theme = .system } label: {
                        Label(state.text("system"), systemImage: state.theme == .system ? "checkmark" : "circle.lefthalf.filled")
                    }
                }
            }
        }
    }
}

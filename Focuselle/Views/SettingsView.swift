import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    var body: some View {
        Form {
            Section(state.text("appearance")) {
                Picker(state.text("theme"), selection: $state.theme) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        Text(state.text(theme.rawValue)).tag(theme)
                    }
                }.pickerStyle(.segmented)
                Picker(state.text("language"), selection: $state.language) {
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
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
        }.formStyle(.grouped)
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

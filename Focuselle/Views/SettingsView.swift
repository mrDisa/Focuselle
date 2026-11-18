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
            Section(state.text("controls")) {
                LabeledContent(state.text("navigation"), value: "⌘1 – ⌘6")
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

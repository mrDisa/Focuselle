import SwiftUI

struct TimerTransport: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 16) {
            Button { state.toggleTimer() } label: {
                Image(systemName: state.timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 18)).frame(width: 50, height: 44)
            }
            .buttonStyle(.borderedProminent).tint(.primary)
            .help(state.text(state.transportTitle)).accessibilityLabel(state.text(state.transportTitle))
            .disabled(state.timer.remaining == 0)
            Button { state.resetTimer() } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 28, height: 32)
            }
            .buttonStyle(.borderless).disabled(!state.hasProgress && !state.timer.isRunning)
            .help(state.text("reset")).accessibilityLabel(state.text("reset"))
        }
    }
}

struct MiniTimerView: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(spacing: 17) {
            Text(state.text(state.timer.remaining == 0 ? "completed" : state.phaseTitle))
                .font(.caption).foregroundStyle(.secondary)
            Text(state.digits).font(.system(size: 43, weight: .medium, design: .monospaced)).monospacedDigit()
            TimerTransport(state: state)
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(state.theme.scheme)
            .environment(\.locale, state.locale)
    }
}

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var state: AppState
    var showMain: () -> Void
    var showMini: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Text("Focuselle").font(.headline)
            MiniTimerView(state: state).frame(height: 190)
            Divider()
            Button(state.text("openFocuselle")) {
                openWindow(id: "main")
                showMain()
            }
            Button(state.text("miniTimer"), action: showMini)
            Divider()
            Button(state.text("quit")) { NSApplication.shared.terminate(nil) }
        }.buttonStyle(.plain).padding(18).frame(width: 280)
            .preferredColorScheme(state.theme.scheme)
    }
}

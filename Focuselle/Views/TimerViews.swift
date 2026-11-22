import SwiftUI

struct FocusPalette {
    var phase: FocusTimer.Phase
    var dark: Bool
    var accent: Color { Color(hex: phase == .focus ? (dark ? 0x86A591 : 0x42634F) : (dark ? 0x8DAEA2 : 0x426D60)) }
    var highlight: Color { Color(hex: dark ? (phase == .focus ? 0x2E4D3B : 0x304F45) : (phase == .focus ? 0xD3E0D4 : 0xD0DFD8)) }
    var background: Color { Color(hex: dark ? 0x101112 : 0xF5F6F3) }
    var surface: Color { Color.primary.opacity(dark ? 0.035 : 0.025) }
    var border: Color { Color.primary.opacity(dark ? 0.08 : 0.07) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct FocusPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct FocusDial: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    private var palette: FocusPalette { FocusPalette(phase: state.timer.phase, dark: scheme == .dark) }
    var body: some View {
        ZStack {
            // Graphite face and a restrained forest-green progress track.
            Circle()
                .fill(LinearGradient(colors: [Color(hex: scheme == .dark ? 0x1B1E1D : 0xFFFFFF),
                                             Color(hex: scheme == .dark ? 0x111313 : 0xEFF2EE)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.015)],
                                                               startPoint: .top, endPoint: .bottom)))
                .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 16, x: 0, y: 10)
                .padding(12)
            Circle().stroke(palette.accent.opacity(0.10), lineWidth: 6).padding(25)
            Circle().trim(from: 0, to: max(0, min(1, state.progress)))
                .stroke(AngularGradient(colors: [palette.accent.opacity(0.35), palette.accent.opacity(0.75), palette.accent],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(25)
            if state.progress > 0 {
                Circle().fill(palette.accent).frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(palette.background, lineWidth: 2))
                    .offset(y: -138).rotationEffect(.degrees(360 * max(0, min(1, state.progress))))
            }
            VStack(spacing: 13) {
                HStack(spacing: 6) {
                    Circle().fill(palette.accent).frame(width: 5, height: 5)
                    Text(state.text(state.timer.remaining == 0 ? "completed" : state.phaseTitle))
                        .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                }.foregroundStyle(palette.accent)
                Text(state.digits)
                    .font(.system(size: 72, weight: .regular, design: .rounded)).monospacedDigit().tracking(-2)
                    .foregroundStyle(scheme == .dark ? Color(hex: 0xF0F2F0) : Color(hex: 0x27352D))
                    .contentTransition(.identity)
                Text(state.text(state.timer.isRunning ? "stayHere" : "yourPace"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 326, height: 326)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.text(state.phaseTitle))
        .accessibilityValue(state.digits)
    }
}

struct TimerTransport: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    private var palette: FocusPalette { FocusPalette(phase: state.timer.phase, dark: scheme == .dark) }
    var body: some View {
        HStack(spacing: 12) {
            Button { state.toggleTimer() } label: {
                HStack(spacing: 10) {
                    Image(systemName: state.timer.isRunning ? "pause.fill" : "play.fill").font(.system(size: 13, weight: .semibold))
                    Text(state.text(state.transportTitle)).font(.system(size: 14, weight: .semibold))
                }
                .frame(minWidth: 126, minHeight: 48)
                .foregroundStyle(Color(hex: scheme == .dark ? 0xEDF3EE : 0x25372B))
                .background(palette.highlight, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.white.opacity(0.14)))
                .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(FocusPressStyle())
            .help(state.text(state.transportTitle)).accessibilityLabel(state.text(state.transportTitle))
            .disabled((state.timer.remaining == 0 && !state.autoAdvance) || !state.storageReady)
            Button { state.resetTimer() } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary).frame(width: 48, height: 48)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(palette.border))
            }
            .buttonStyle(FocusPressStyle()).disabled((!state.hasProgress && !state.timer.isRunning) || !state.storageReady)
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
            if state.storageError != nil {
                Button(state.text("retryStorage")) { state.retryStorage() }.font(.caption)
                    .help(state.text("storageErrorTitle"))
            }
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

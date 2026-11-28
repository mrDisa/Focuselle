import SwiftUI

struct FocusPalette {
    var phase: FocusTimer.Phase
    var dark: Bool
    var style: VisualStyle = .focuselle
    var accent: Color {
        switch style {
        case .focuselle:
            return Color(hex: dark ? 0xF2F2F2 : 0x171717)
        case .classic:
            return Color(hex: phase == .focus
                ? (dark ? 0x86A591 : 0x42634F)
                : (dark ? 0x8DAEA2 : 0x426D60))
        case .midnight:
            return Color(hex: dark ? 0x58A6FF : 0x0969DA)
        }
    }

    var highlight: Color {
        switch style {
        case .focuselle:
            return Color(hex: dark ? 0xF2F2F2 : 0x171717)
        case .classic:
            return Color(hex: dark
                ? (phase == .focus ? 0x2E4D3B : 0x304F45)
                : (phase == .focus ? 0xD3E0D4 : 0xD0DFD8))
        case .midnight:
            return Color(hex: dark ? 0x1F6FEB : 0x0969DA)
        }
    }

    var buttonInk: Color {
        switch style {
        case .focuselle:
            return Color(hex: dark ? 0x171717 : 0xFFFFFF)
        case .classic:
            return Color(hex: dark ? 0xEDF3EE : 0x25372B)
        case .midnight:
            return .white
        }
    }

    var selectionInk: Color {
        if style == .midnight {
            return Color(hex: dark ? 0x0D1117 : 0xFFFFFF)
        }
        return buttonInk
    }

    var ink: Color {
        switch style {
        case .focuselle:
            return Color(hex: dark ? 0xF6F6F6 : 0x171717)
        case .classic:
            return Color(hex: dark ? 0xF0F2F0 : 0x27352D)
        case .midnight:
            return Color(hex: dark ? 0xE6EDF3 : 0x1F2328)
        }
    }

    var background: Color {
        switch style {
        case .focuselle:
            return Color(hex: dark ? 0x141414 : 0xF4F4F4)
        case .classic:
            return Color(hex: dark ? 0x101112 : 0xF5F6F3)
        case .midnight:
            return Color(hex: dark ? 0x0D1117 : 0xF6F8FA)
        }
    }

    var panel: Color {
        switch style {
        case .focuselle:
            return Color(hex: dark ? 0x202020 : 0xFFFFFF)
        case .classic:
            return Color(hex: dark ? 0x191B1C : 0xEEF0EB)
        case .midnight:
            return Color(hex: dark ? 0x161B22 : 0xFFFFFF)
        }
    }

    var dialTop: Color {
        switch style {
        case .focuselle:
            return background
        case .classic:
            return Color(hex: dark ? 0x1B1E1D : 0xFFFFFF)
        case .midnight:
            return Color(hex: dark ? 0x161B22 : 0xFFFFFF)
        }
    }

    var dialBottom: Color {
        switch style {
        case .focuselle:
            return background
        case .classic:
            return Color(hex: dark ? 0x111313 : 0xEFF2EE)
        case .midnight:
            return Color(hex: dark ? 0x0D1117 : 0xEAEFF5)
        }
    }

    var surface: Color {
        switch style {
        case .focuselle, .midnight:
            return panel
        case .classic:
            return Color.primary.opacity(dark ? 0.035 : 0.025)
        }
    }

    var border: Color {
        switch style {
        case .focuselle:
            return Color(hex: dark ? 0x333333 : 0xE5E5E5)
        case .classic:
            return Color.primary.opacity(dark ? 0.08 : 0.07)
        case .midnight:
            return Color(hex: dark ? 0x30363D : 0xD0D7DE)
        }
    }

    func radius(_ original: CGFloat) -> CGFloat { original }
    var pill: FocusControlShape { FocusControlShape(softRectangle: false) }
}

// Preserve the original green style’s Capsule geometry, including inset borders.
struct FocusControlShape: InsettableShape {
    var softRectangle: Bool
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        if softRectangle { return RoundedRectangle(cornerRadius: 18, style: .continuous).inset(by: insetAmount).path(in: rect) }
        return Capsule().inset(by: insetAmount).path(in: rect)
    }
    func inset(by amount: CGFloat) -> Self {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var palette: FocusPalette { FocusPalette(phase: state.timer.phase, dark: scheme == .dark, style: state.visualStyle) }
    var body: some View {
        ZStack {
            switch state.timerFace {
            case .ring: classicFace.transition(.opacity)
            case .scale: editorialFace.transition(.opacity)
            case .minimal: minimalFace.transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: state.timerFace)
        .frame(width: 326, height: 326)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.text(state.phaseTitle))
        .accessibilityValue(state.digits)
    }


    private var progressValue: CGFloat {
        CGFloat(max(0, min(1, state.progress)))
    }

    private var sharedFace: some View {
        ZStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 5, height: 5)

                Text(state.text(
                    state.timer.remaining == 0
                    ? "completed" : state.phaseTitle
                ))
                .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .position(x: 163, y: 100)

            Text(state.digits)
                .font(.system(size: 72,
                              weight: .regular,
                              design: .rounded))
                .monospacedDigit()
                .tracking(-2)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: 248, height: 90)
                .contentTransition(.identity)
                .position(x: 163, y: 163)

            Text(state.text(
                state.timer.isRunning
                ? "stayHere" : "yourPace"
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .position(x: 163, y: 225)
        }
        .frame(width: 326, height: 326)
    }

    private var editorialFace: some View {
        ZStack {
            sharedFace

            HStack(spacing: 4) {
                ForEach(0..<41, id: \.self) { tick in
                    let current = Int(
                        (progressValue * 40).rounded()
                    )

                    Capsule()
                        .fill(palette.accent.opacity(
                            tick == current ? 1 :
                            (tick <= current ? 0.42 : 0.10)
                        ))
                        .frame(
                            width: 2,
                            height: tick == current ? 22 :
                            (tick.isMultiple(of: 5) ? 14 : 7)
                        )
                }
            }
            .frame(height: 22)
            .position(x: 163, y: 266)
        }
    }

    private var minimalFace: some View {
        ZStack {
            sharedFace

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.accent.opacity(0.12))

                Capsule()
                    .fill(palette.accent)
                    .frame(width: 132 * progressValue)
            }
            .frame(width: 132, height: 3)
            .position(x: 163, y: 266)
        }
    }

    private var classicFace: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            palette.dialTop,
                            palette.dialBottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle().strokeBorder(
                        Color.white.opacity(0.06)
                    )
                )
                .padding(12)

            Circle()
                .stroke(
                    palette.accent.opacity(0.10),
                    lineWidth: 6
                )
                .padding(25)

            Circle()
                .trim(from: 0, to: progressValue)
                .stroke(
                    palette.accent,
                    style: StrokeStyle(
                        lineWidth: 6,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .padding(25)

            sharedFace
        }
    }
}

struct TimerTransport: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    private var palette: FocusPalette { FocusPalette(phase: state.timer.phase, dark: scheme == .dark, style: state.visualStyle) }
    var body: some View {
        HStack(spacing: 12) {
            Button { state.toggleTimer() } label: {
                HStack(spacing: 10) {
                    Image(systemName: state.timer.isRunning ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .semibold))
                    Text(state.text(state.transportTitle)).font(.system(size: 12, weight: .semibold))
                }
                .frame(minWidth: 140, minHeight: 44)
                .foregroundStyle(palette.buttonInk)
                .background(palette.highlight, in: RoundedRectangle(cornerRadius: palette.radius(11)))
                .overlay(RoundedRectangle(cornerRadius: palette.radius(11)).strokeBorder(Color.white.opacity(0.14)))
                .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(FocusPressStyle())
            .help(state.text(state.transportTitle)).accessibilityLabel(state.text(state.transportTitle))
            .disabled((state.timer.remaining == 0 && !state.autoAdvance) || !state.storageReady)
            Button { state.resetTimer() } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary).frame(width: 44, height: 44)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: palette.radius(11)))
                    .overlay(RoundedRectangle(cornerRadius: palette.radius(11)).strokeBorder(palette.border))
            }
            .buttonStyle(FocusPressStyle()).disabled((!state.hasProgress && !state.timer.isRunning) || !state.storageReady)
            .help(state.text("reset")).accessibilityLabel(state.text("reset"))
        }
    }
}

struct MiniTimerView: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    private var palette: FocusPalette { FocusPalette(phase: state.timer.phase, dark: scheme == .dark, style: state.visualStyle) }
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
            .background {
                palette.background
            }
            .tint(palette.accent)
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

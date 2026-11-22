import SwiftUI

// Disambiguate the property wrapper from the new SDK macro for CLT builds.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct WorkspaceView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var updates: UpdateController
    var showMini: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState<Bool> private var showCustom = false
    @ViewState<Int> private var customWork = 40
    @ViewState<Int> private var customRest = 8
    private var palette: FocusPalette { FocusPalette(phase: state.timer.phase, dark: scheme == .dark) }
    private var locked: Bool { state.timer.isRunning || state.hasProgress || !state.storageReady }

    init(state: AppState, showMini: @escaping () -> Void) {
        self.state = state
        self.updates = state.updates
        self.showMini = showMini
    }

    var body: some View {
        GeometryReader { geometry in
            let minimal = state.screen == .focus && (geometry.size.width < 390 || geometry.size.height < 560)
            HStack(spacing: 0) {
                if minimal {
                    minimalFocus(size: geometry.size)
                } else {
                    navigation
                    Rectangle().fill(palette.border).frame(width: 1)
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                header
                                StorageStatusView(state: state)
                                content(compact: geometry.size.height < 780)
                            }
                            .padding(.horizontal, geometry.size.width < 540 ? 16 : 24).padding(.vertical, 20)
                            .frame(maxWidth: 800).frame(maxWidth: .infinity)
                            .background(QuietScrollStyle())
                        }.id(state.screen)
                        footer
                    }
                    if state.showPlan && geometry.size.width >= 1000 {
                        Rectangle().fill(palette.border).frame(width: 1)
                        dayPlan.frame(width: 260)
                    }
                }
            }
            .background(palette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: showMini) { toolbarGlyph("pip") }
                        .controlSize(.regular)
                        .help(state.text("miniTimer"))
                    if minimal {
                        Button {
                            NSApp.keyWindow?.setContentSize(NSSize(width: 650, height: 740))
                        } label: { toolbarGlyph("arrow.up.left.and.arrow.down.right") }
                        .help(state.text("expandWorkspace"))
                    } else {
                        Button { state.showPlan.toggle() } label: { toolbarGlyph("sidebar.right") }
                            .controlSize(.regular)
                            .help(state.text("togglePlan"))
                    }
                }
            }
        }
        .sheet(item: $state.editingTask) { task in TaskEditorView(state: state, task: task) }
        .controlSize(.small)
        .tint(palette.accent)
        .frame(minWidth: 340, minHeight: 400)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: state.timer.phase)
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
    }

    private func toolbarGlyph(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 15, weight: .medium))
            .frame(width: 26, height: 24).contentShape(Rectangle())
    }

    private var footer: some View {
        HStack {
            Label(state.text("localOnly"), systemImage: "internaldrive")
            Spacer()
            Button { state.soundEnabled.toggle() } label: {
                Label(state.text(state.soundEnabled ? "transitionSounds" : "silence"),
                      systemImage: state.soundEnabled ? "speaker.wave.2" : "speaker.slash")
            }.buttonStyle(.plain).help(state.text("transitionSounds"))
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 20).padding(.vertical, 11)
        .background(palette.background)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private func minimalFocus(size: CGSize) -> some View {
        let diameter = max(180, min(290, size.width - 40, size.height - 110))
        return VStack(spacing: 18) {
            FocusDial(state: state)
                .scaleEffect(diameter / 326)
                .frame(width: diameter, height: diameter)
            TimerTransport(state: state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date.now.formatted(.dateTime.locale(state.locale).weekday(.wide).day().month(.wide)))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            HStack(alignment: .center) {
                Text(state.text(state.screen.titleKey))
                    .font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-1)
                Spacer(minLength: 8)
                if state.screen == .focus {
                    Label(state.text(state.timer.isRunning ? "sessionActive" : "readyToFocus"),
                          systemImage: state.timer.isRunning ? "waveform" : "sparkle")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(palette.accent)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(palette.accent.opacity(0.09), in: Capsule())
                }
            }
        }
    }

    private var navigation: some View {
        VStack(spacing: 4) {
            ForEach(Screen.allCases.filter { $0 != .settings }) { item in navButton(item) }
            Spacer(minLength: 16)
            if let version = updates.availableVersion {
                Button { updates.checkForUpdates() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 17))
                        Text(state.text("update")).font(.system(size: 8, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(palette.accent)
                    .frame(width: 48, height: 46)
                    .background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(FocusPressStyle())
                .help(state.text("updateAvailable") + " · " + version)
                .accessibilityLabel(state.text("updateAvailable") + " " + version)
            }
            navButton(.settings)
        }
        .padding(.vertical, 8).frame(width: 52).frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func navButton(_ item: Screen) -> some View {
        Button { state.screen = item } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(state.screen == item ? palette.accent.opacity(0.12) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(state.screen == item ? palette.accent.opacity(0.18) : .clear))
                    .frame(width: 34, height: 32)
                Image(systemName: item.symbol).font(.system(size: 16, weight: .medium))
                    .foregroundStyle(state.screen == item ? palette.accent : Color.secondary)
                if state.screen == item {
                    Capsule().fill(palette.accent).frame(width: 3, height: 18).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: 52, height: 48)
            .overlay(alignment: .bottom) {
                if state.commandHeld {
                    Text("⌘\(item.shortcutNumber)").font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.accent).padding(.bottom, 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(FocusPressStyle())
        .help(state.text(item.titleKey) + " · ⌘\(item.shortcutNumber)")
        .accessibilityLabel(state.text(item.titleKey))
        .accessibilityAddTraits(state.screen == item ? .isSelected : [])
    }

    @ViewBuilder private func content(compact: Bool) -> some View {
        switch state.screen {
        case .focus: focus(compact: compact)
        case .settings: SettingsView(state: state)
        case .tasks: PlannerCalendarView(state: state)
        case .statistics: StatisticsView(state: state)
        case .sounds: StageNotice(state: state, icon: "headphones", title: "soundsNext", detail: "soundsDetail")
        }
    }

    private func focus(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { presetControls }
                    .fixedSize(horizontal: true, vertical: false)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    presetControls
                }
            }
            .padding(6).background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.border))

            HStack(spacing: 4) {
                phaseButton("focus", phase: .focus)
                phaseButton("shortBreak", phase: .shortBreak)
                phaseButton("longBreak", phase: .longBreak)
            }
            .padding(4).background(palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.border))

            taskSelector

            FocusDial(state: state)
                .scaleEffect(compact ? 0.66 : 0.88)
                .frame(width: compact ? 216 : 287, height: compact ? 216 : 287)
                .padding(.vertical, 2)
            TimerTransport(state: state)

            if !compact {
                HStack(spacing: 8) {
                    Image(systemName: state.autoAdvance ? "repeat" : "arrow.right.circle")
                    Text(state.text(state.autoAdvance ? "automaticCycle" : "manualCycle"))
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var presetControls: some View {
        ForEach(state.presets.filter(\.isPinned)) { preset in
            presetButton("\(preset.focusMinutes) / \(preset.shortBreakMinutes)",
                         selected: state.workMinutes == preset.focusMinutes && state.restMinutes == preset.shortBreakMinutes) {
                state.selectPreset(work: preset.focusMinutes, rest: preset.shortBreakMinutes)
            }
        }
        presetButton(state.text("customPreset"), selected: !state.presets.contains { $0.focusMinutes == state.workMinutes && $0.shortBreakMinutes == state.restMinutes }) {
            customWork = state.workMinutes
            customRest = state.restMinutes
            showCustom = true
        }
        .popover(isPresented: $showCustom) {
            VStack(alignment: .leading, spacing: 18) {
                Text(state.text("customPreset")).font(.headline)
                Stepper(value: $customWork, in: 1...240) {
                    Text("\(state.text("focus")): \(customWork) \(state.text("minutes"))")
                }
                Stepper(value: $customRest, in: 1...120) {
                    Text("\(state.text("shortBreak")): \(customRest) \(state.text("minutes"))")
                }
                Button(state.text("applyPreset")) {
                    state.selectPreset(work: customWork, rest: customRest)
                    showCustom = false
                }.buttonStyle(.borderedProminent).disabled(locked)
            }.padding(24).frame(width: 300)
        }
    }

    private var taskSelector: some View {
            Menu {
                Button(state.text("withoutTask")) { state.chooseTask(nil) }
                ForEach(state.dayTasks.filter { !$0.isCompleted }) { task in
                    Button(task.title) { state.chooseTask(task) }
                }
                Divider()
                Button(state.text("openTasks")) { state.screen = .tasks }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "scope").foregroundStyle(palette.accent)
                    Text(state.currentTaskTitle ?? state.text("chooseFocusTask")).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                }
                .font(.system(size: 12, weight: .medium))

            }
            .menuStyle(.borderlessButton).frame(width: 230)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.border))
            .disabled(locked).help(state.text("focusOnTask"))

    }

    private func presetButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .medium)).monospacedDigit()
                .foregroundStyle(selected ? palette.accent : Color.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(FocusPressStyle()).disabled(locked)
    }

    private func phaseButton(_ title: String, phase: FocusTimer.Phase) -> some View {
        Button { state.selectPhase(phase) } label: {
            Text(state.text(title)).font(.system(size: 11, weight: .medium))
                .foregroundStyle(state.timer.phase == phase ? Color.primary : .secondary)
                .padding(.horizontal, 8).padding(.vertical, 7)
                .background(state.timer.phase == phase ? palette.accent.opacity(0.16) : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(state.timer.phase == phase ? palette.accent.opacity(0.25) : .clear))
        }.buttonStyle(FocusPressStyle()).disabled(locked)
            .accessibilityAddTraits(state.timer.phase == phase ? .isSelected : [])
    }

    private var dayPlan: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(state.text("dayPlan")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(state.dayTasks.filter(\.isCompleted).count)/\(state.dayTasks.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(state.selectedDate.formatted(.dateTime.locale(state.locale).day().month(.wide)))
                .font(.system(size: 25, weight: .medium, design: .rounded)).tracking(-0.6)
            PlannerDatePicker(state: state)
            Divider()
            ScrollView { TaskRows(state: state).background(QuietScrollStyle()) }
            Button { state.screen = .tasks } label: {
                Label(state.text("openTasks"), systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.bordered)
        }.padding(24).frame(maxHeight: .infinity).background(.ultraThinMaterial)
    }
}

struct StageNotice: View {
    @ObservedObject var state: AppState
    var icon: String
    var title: String
    var detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(state.text(title)).font(.title2)
            Text(state.text(detail)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.07)))
    }
}

// Keep native scrolling and hit testing, with a quieter overlay indicator.
private struct QuietScrollStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.scheduleUpdate() }

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleUpdate()
        }
        func scheduleUpdate() {
            DispatchQueue.main.async { [weak self] in
                guard let scroll = self?.enclosingScrollView else { return }
                if !(scroll.verticalScroller is QuietScroller) {
                    scroll.verticalScroller = QuietScroller()
                }
                scroll.scrollerStyle = .overlay
                scroll.autohidesScrollers = true
                scroll.verticalScroller?.controlSize = .small
            }
        }
    }
}

private final class QuietScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) { }
    override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.height > 0 else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor(white: 0.24, alpha: 0.65) : NSColor(white: 0.2, alpha: 0.25)).setFill()
        let height = max(12, knob.height - 6)
        let slim = NSRect(x: knob.midX - 1.5, y: knob.midY - height / 2, width: 3, height: height)
        NSBezierPath(roundedRect: slim, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

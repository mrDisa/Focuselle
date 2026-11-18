import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var state: AppState
    var showMini: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            navigation
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(Date.now.formatted(.dateTime.locale(state.locale).weekday(.wide).day().month(.wide)))
                        .font(.callout).foregroundStyle(.secondary)
                    Text(state.text(state.screen.rawValue))
                        .font(.system(size: 44, weight: .medium)).tracking(-2)
                    content
                }
                .padding(40)
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            if state.showPlan {
                Divider()
                dayPlan.frame(width: 265)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: state.showPlan ? 1000 : 735, minHeight: 650)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Focuselle").font(.system(size: 16, weight: .semibold)).tracking(-0.7)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: showMini) { Image(systemName: "pip") }
                    .help(state.text("miniTimer"))
                Button { state.showPlan.toggle() } label: { Image(systemName: "sidebar.right") }
                    .help(state.text("togglePlan"))
            }
        }
    }

    private var navigation: some View {
        VStack(spacing: 10) {
            ForEach(Screen.allCases.filter { $0 != .settings }) { item in navButton(item) }
            Spacer()
            navButton(.settings)
        }
        .padding(.vertical, 26).padding(.horizontal, 12).frame(width: 68)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func navButton(_ item: Screen) -> some View {
        Button { state.screen = item } label: {
            Image(systemName: item.symbol).font(.system(size: 19, weight: .regular))
                .frame(width: 42, height: 42)
                .background(state.screen == item ? Color.primary.opacity(0.09) : .clear,
                            in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain).help(state.text(item.rawValue))
        .accessibilityLabel(state.text(item.rawValue))
        .accessibilityAddTraits(state.screen == item ? .isSelected : [])
    }

    @ViewBuilder private var content: some View {
        switch state.screen {
        case .focus: focus
        case .settings: SettingsView(state: state)
        case .calendar:
            DatePicker(state.text("planDate"), selection: $state.selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
            StageNotice(state: state, icon: "calendar", title: "calendarNext", detail: "calendarDetail")
        case .tasks:
            StageNotice(state: state, icon: "checklist", title: "tasksNext", detail: "tasksDetail")
        case .statistics:
            StageNotice(state: state, icon: "chart.bar", title: "statisticsNext", detail: "statisticsDetail")
        case .sounds:
            StageNotice(state: state, icon: "headphones", title: "soundsNext", detail: "soundsDetail")
        }
    }

    private var focus: some View {
        VStack(spacing: 28) {
            HStack(spacing: 8) {
                ForEach([25, 50, 90], id: \.self) { minutes in
                    Button("\(minutes) / \(minutes == 25 ? 5 : 10)") {
                        state.selectPreset(work: minutes, rest: minutes == 25 ? 5 : 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(state.workMinutes == minutes ? .primary : .secondary)
                    .disabled(state.timer.isRunning || state.hasProgress)
                }
                Spacer()
            }
            HStack {
                phaseButton("focus", phase: .focus)
                phaseButton("shortBreak", phase: .shortBreak)
                phaseButton("longBreak", phase: .longBreak)
            }
            ZStack {
                Circle().fill(Color.primary.opacity(0.045))
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                Circle().trim(from: 0, to: state.progress)
                    .stroke(Color.primary.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 12) {
                    Text(state.text(state.timer.remaining == 0 ? "completed" : state.phaseTitle))
                        .font(.callout).foregroundStyle(.secondary)
                    Text(state.digits).font(.system(size: 65, weight: .regular, design: .monospaced))
                        .tracking(-5).monospacedDigit()
                    Text(state.text(state.timer.isRunning ? "stayHere" : "yourPace"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 300, height: 300)
            .accessibilityElement(children: .combine)
            TimerTransport(state: state)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(state.text("currentTask")).font(.caption).foregroundStyle(.secondary)
                    Text(state.text("withoutTask")).font(.body)
                }
                Spacer()
                Label(state.text("silence"), systemImage: "speaker.slash")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(state.text("prototypeNotice")).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func phaseButton(_ title: String, phase: FocusTimer.Phase) -> some View {
        Button(state.text(title)) { state.selectPhase(phase) }
            .buttonStyle(.bordered).tint(state.timer.phase == phase ? .primary : .secondary)
            .disabled(state.timer.isRunning || state.hasProgress)
    }

    private var dayPlan: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(state.text("dayPlan")).font(.callout).foregroundStyle(.secondary)
            Text(state.selectedDate.formatted(.dateTime.locale(state.locale).day().month(.wide)))
                .font(.system(size: 24, weight: .medium)).tracking(-0.7)
            DatePicker(state.text("planDate"), selection: $state.selectedDate, displayedComponents: .date)
                .labelsHidden().datePickerStyle(.field)
            Divider()
            Image(systemName: "checklist").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(state.text("emptyPlan")).font(.headline)
            Text(state.text("planDetail")).font(.callout).foregroundStyle(.secondary)
            Button(state.text("openTasks")) { state.screen = .tasks }.buttonStyle(.bordered)
            Spacer()
        }.padding(24).frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
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
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
    }
}

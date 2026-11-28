import SwiftUI
import Charts

struct StorageStatusView: View {
    @ObservedObject var state: AppState
    var body: some View {
        if let error = state.storageError {
            VStack(alignment: .leading, spacing: 8) {
                Label(state.text("storageErrorTitle"), systemImage: "exclamationmark.triangle")
                Text(error).font(.caption).textSelection(.enabled)
                Button(state.text("retryStorage")) { state.retryStorage() }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        } else if state.restoredSession {
            Label(state.text("restoredSession"), systemImage: "pause.circle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct TaskRows: View {
    @ObservedObject var state: AppState
    @PlannerState<FocusTask?> private var pendingDeletion = nil
    @Environment(\.colorScheme) private var scheme
    private var palette: FocusPalette { FocusPalette(phase: state.timer.phase, dark: scheme == .dark, style: state.visualStyle) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.dayTasks.isEmpty {
                Label(state.text("noTasks"), systemImage: "checklist")
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 18)
            }
            ForEach(state.dayTasks) { task in
                HStack(alignment: .center, spacing: 10) {
                    Button { state.toggleTask(task) } label: {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(task.isCompleted ? (state.visualStyle == .classic ? Color.accentColor : palette.accent) : Color.secondary)
                            .frame(width: 28, height: 32).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(state.text(task.isCompleted ? "markIncomplete" : "markComplete"))
                        .disabled(!state.storageReady)
                    Button { state.editingTask = task } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(task.title).strikethrough(task.isCompleted).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !task.details.isEmpty {
                                Text(task.details).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(state.text("editTask"))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(state.visualStyle == .focuselle ? palette.background : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: palette.radius(12)))
                .contentShape(RoundedRectangle(cornerRadius: palette.radius(12)))
                .contextMenu {
                    Button(state.text("focusOnTask")) { state.chooseTask(task) }
                        .disabled(task.isCompleted || state.timer.isRunning || state.hasProgress || !state.storageReady)
                    Button(state.text("editTask")) { state.editingTask = task }
                    Divider()
                    Button(state.text("deleteTask"), role: .destructive) { pendingDeletion = task }
                }
            }
        }
        .confirmationDialog(state.text("deleteTask"), isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible) {
            if let task = pendingDeletion {
                Button(state.text("deleteTask"), role: .destructive) { state.deleteTask(task); pendingDeletion = nil }
            }
            Button(state.text("cancel"), role: .cancel) { pendingDeletion = nil }
        } message: { Text(state.text("deleteTaskDetail")) }
    }
}

struct TaskEditorView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var palette: FocusPalette { FocusPalette(phase: state.timer.phase, dark: scheme == .dark, style: state.visualStyle) }
    @PlannerState<FocusTask> private var draft: FocusTask
    init(state: AppState, task: FocusTask) {
        self.state = state
        _draft = PlannerState(initialValue: task)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(state.text(state.tasks.contains { $0.id == draft.id } ? "editTask" : "newTask"))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(state.text("taskTitle")).font(.caption).foregroundStyle(.secondary)
            TextField(state.text("taskTitle"), text: $draft.title).textFieldStyle(.roundedBorder)
            Text(state.text("taskDescription")).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $draft.details).font(.body).scrollContentBackground(.hidden)
                .padding(10).frame(height: 140)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: palette.radius(12)))
                .overlay(RoundedRectangle(cornerRadius: palette.radius(12)).strokeBorder(Color.primary.opacity(0.08)))
                .accessibilityLabel(state.text("taskDescription"))
            if let error = state.storageError {
                Text(error).font(.caption).foregroundStyle(.red)
                Button(state.text("retryStorage")) { state.retryStorage() }
            }
            HStack {
                Spacer()
                Button(state.text("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(state.text("saveTask")) {
                    if state.saveTask(draft) { dismiss() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.storageReady)
            }
        }.padding(28).frame(width: 440)
            .background(palette.background)
            .tint(palette.accent)
            .preferredColorScheme(state.theme.scheme).environment(\.locale, state.locale)
    }
}

struct StatisticsView: View {
    @ObservedObject var state: AppState
    @PlannerState<Int> private var range = 7
    @Environment(\.colorScheme) private var scheme
    private var palette: FocusPalette { FocusPalette(phase: .focus, dark: scheme == .dark, style: state.visualStyle) }
    private var insights: FocusInsights { FocusInsights(sessions: state.sessions, endingAt: state.selectedDate, count: range) }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                PlannerDatePicker(state: state)
                Spacer()
                FocusSegments(selection: $range, options: [(7, state.text("sevenDays")), (30, state.text("thirtyDays"))], palette: palette)
                    .frame(width: 174)
            }
            HStack(spacing: 12) {
                metric("timer", title: "focusTime", value: duration(insights.totalSeconds))
                metric("checkmark.circle", title: "completedSessions", value: "\(insights.completedCount)")
                metric("calendar", title: "activeDays", value: "\(insights.activeDays) / \(range)")
            }
            VStack(alignment: .leading, spacing: 18) {
                Text(state.text("focusByDay")).font(.system(size: 17, weight: .semibold))
                Chart(insights.days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value(state.text("minutes"), day.completedSeconds / 60))
                        .foregroundStyle(by: .value("Status", state.text("completedSessions")))
                        .cornerRadius(3)
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value(state.text("minutes"), day.interruptedSeconds / 60))
                        .foregroundStyle(by: .value("Status", state.text("interruptedSessions")))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale([state.text("completedSessions"): palette.accent,
                                            state.text("interruptedSessions"): palette.accent.opacity(0.30)])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: range == 7 ? 1 : 7)) {
                        AxisValueLabel(format: .dateTime.locale(state.locale).day().month(.abbreviated))
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartYScale(domain: 0...max(10, (insights.days.map(\.totalSeconds).max() ?? 0) / 60 * 1.15))
                .frame(height: 200)
                if insights.sessions.isEmpty {
                    Text(state.text("noInsights")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text(state.text("insightsMethod")).font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(22).background(palette.surface, in: RoundedRectangle(cornerRadius: palette.radius(20)))
                .overlay(RoundedRectangle(cornerRadius: palette.radius(20)).strokeBorder(palette.border))
            if !insights.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    Text(state.text("timeByTask")).font(.system(size: 17, weight: .semibold))
                    ForEach(Array(insights.tasks.prefix(5))) { task in
                        VStack(spacing: 8) {
                            HStack {
                                Text(task.title ?? state.text("withoutTask")).lineLimit(1)
                                Spacer()
                                Text(duration(task.seconds)).monospacedDigit().foregroundStyle(.secondary)
                            }.font(.system(size: 12))
                            GeometryReader { geometry in
                                Capsule().fill(palette.accent.opacity(0.08))
                                Capsule().fill(palette.accent.opacity(0.7))
                                    .frame(width: geometry.size.width * (insights.totalSeconds > 0 ? task.seconds / insights.totalSeconds : 0))
                            }.frame(height: 5)
                        }
                    }
                }.padding(22).background(palette.surface, in: RoundedRectangle(cornerRadius: palette.radius(20)))
            }
            SessionHistoryView(state: state)
        }
    }
    private func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if seconds > 0 && minutes == 0 { return "< 1 " + state.text("minutes") }
        return minutes >= 60 ? "\(minutes / 60) \(state.text("hoursShort")) \(minutes % 60) \(state.text("minutes"))" : "\(minutes) \(state.text("minutes"))"
    }
    private func metric(_ icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(state.text(title), systemImage: icon).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(2).frame(height: 28, alignment: .topLeading)
            Text(value).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: palette.radius(14)))
    }
}

struct SessionHistoryView: View {
    @ObservedObject var state: AppState
    private var sessions: [FocusSession] { state.sessions.filter { $0.localDay == state.selectedDay }.reversed() }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(state.text("sessionHistory")).font(.title2)
            if sessions.isEmpty { Text(state.text("noSessions")).foregroundStyle(.secondary) }
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 7) {
                    Text(session.taskTitle ?? state.text("withoutTask")).font(.headline)
                    HStack {
                        Text(state.text(session.status == "completed" ? "completed" : "interrupted"))
                        Spacer()
                        Text(String(format: "%.1f", session.focusSeconds / 60) + " " + state.text("minutes"))
                            .monospacedDigit()
                    }.font(.callout).foregroundStyle(.secondary)
                }
                Divider()
            }
        }
    }
}

// Explicit wrapper alias keeps the Command Line Tools build independent of SDK macros.
private typealias PlannerState<Value> = SwiftUI.State<Value>

struct PlannerCalendarView: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    private var palette: FocusPalette { FocusPalette(phase: state.timer.phase, dark: scheme == .dark, style: state.visualStyle) }
    private var focusMinutes: Int {
        Int(state.sessions.filter { $0.localDay == state.selectedDay }.reduce(0) { $0 + $1.focusSeconds } / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PlannerDatePicker(state: state)
            HStack(spacing: 12) {
                metric("checklist", title: "tasks", value: "\(state.dayTasks.count)")
                metric("checkmark.circle", title: "completedTasks", value: "\(state.dayTasks.filter(\.isCompleted).count)")
                metric("timer", title: "focus", value: "\(focusMinutes) \(state.text("minutes"))")
            }
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(state.text("dayPlan")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Text(state.selectedDate.formatted(.dateTime.locale(state.locale).weekday(.wide).day().month(.wide)))
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                    }
                    Spacer()
                    Button { state.newTask() } label: {
                        Label(state.text("newTask"), systemImage: "plus").font(.system(size: 12, weight: .medium))
                    }.buttonStyle(.bordered).disabled(!state.storageReady)
                }
                HStack(spacing: 12) {
                    Image(systemName: "plus").foregroundStyle(palette.accent)
                    TextField(state.text("taskTitle"), text: $state.taskDraft).textFieldStyle(.plain).onSubmit(addTask)
                    Button(state.text("addTask"), action: addTask)
                        .buttonStyle(.bordered)
                        .disabled(state.taskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.storageReady)
                }.padding(12).background(palette.surface, in: RoundedRectangle(cornerRadius: palette.radius(12)))
                TaskRows(state: state)
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: palette.radius(20)))
            .overlay(RoundedRectangle(cornerRadius: palette.radius(20)).strokeBorder(palette.border))
        }
    }

    private func metric(_ icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(state.text(title), systemImage: icon).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(2).frame(height: 28, alignment: .topLeading)
            Text(value).font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: palette.radius(14)))
            .overlay(RoundedRectangle(cornerRadius: palette.radius(14)).strokeBorder(palette.border))
    }

    private func addTask() {
        state.addTask(title: state.taskDraft)
        if state.storageError == nil { state.taskDraft = "" }
    }
}

struct MonthCalendarView: View {
    @ObservedObject var state: AppState
    var small = false
    @PlannerState<Date> private var month = Date()
    @Environment(\.colorScheme) private var scheme
    private var palette: FocusPalette { FocusPalette(phase: state.timer.phase, dark: scheme == .dark, style: state.visualStyle) }
    private var calendar: Calendar { Calendar(identifier: .gregorian) }
    private var dates: [Date] { CalendarMonth.days(containing: month, calendar: calendar) }
    private var weekdayNames: [String] {
        let formatter = DateFormatter()
        formatter.locale = state.locale
        let names = formatter.shortStandaloneWeekdaySymbols ?? []
        return Array(names.dropFirst()) + Array(names.prefix(1))
    }

    var body: some View {
        VStack(spacing: small ? 16 : 24) {
            HStack(spacing: 10) {
                Text(month.formatted(.dateTime.locale(state.locale).month(.wide).year()))
                    .font(.system(size: small ? 17 : 25, weight: .medium, design: .rounded))
                Spacer(minLength: 4)
                Button(state.text("today")) {
                    state.selectedDate = Date()
                    month = state.selectedDate
                }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(palette.accent.opacity(0.10), in: Capsule())
                monthButton(-1, icon: "chevron.left", label: "previousMonth")
                monthButton(1, icon: "chevron.right", label: "nextMonth")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: small ? 4 : 8) {
                ForEach(Array(weekdayNames.enumerated()), id: \.offset) { _, name in
                    Text(name.uppercased()).font(.system(size: 10, weight: .semibold))
                        .tracking(0.5).foregroundStyle(.tertiary).padding(.bottom, 8)
                }
                ForEach(dates, id: \.self) { date in dayButton(date) }
            }
        }
        .padding(small ? 18 : 24)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: palette.radius(20)))
        .overlay(RoundedRectangle(cornerRadius: palette.radius(20)).strokeBorder(palette.border))
        .onAppear { month = state.selectedDate }
        .onChange(of: state.selectedDate) { _, date in month = date }
    }

    private func monthButton(_ delta: Int, icon: String, label: String) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: delta, to: calendar.dateInterval(of: .month, for: month)!.start) { month = next }
        } label: {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28).background(palette.surface, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(FocusPressStyle()).help(state.text(label)).accessibilityLabel(state.text(label))
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: state.selectedDate)
        let today = calendar.isDateInToday(date)
        let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let count = state.tasks.filter { $0.plannedDay == LocalDay.string(date) }.count
        return Button { state.selectedDate = date } label: {
            VStack(spacing: small ? 3 : 7) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: small ? 12 : 15, weight: selected || today ? .semibold : .regular)).monospacedDigit()
                    .foregroundStyle(selected ? palette.accent : Color.primary.opacity(inMonth ? 0.85 : 0.25))
                HStack(spacing: 3) {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        Circle().fill(palette.accent.opacity(inMonth ? 0.85 : 0.3)).frame(width: 3, height: 3)
                    }
                }.frame(height: 3)
            }
            .frame(maxWidth: .infinity).frame(height: small ? 32 : 48)
            .background(selected ? palette.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: small ? 8 : 12))
            .overlay(RoundedRectangle(cornerRadius: small ? 8 : 12)
                .strokeBorder(palette.accent.opacity(selected ? 0.35 : (today ? 0.22 : 0))))
            .contentShape(Rectangle())
        }
        .buttonStyle(FocusPressStyle())
        .accessibilityLabel(date.formatted(.dateTime.locale(state.locale).day().month(.wide).year()) + ", \(state.text("tasks")): \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PlannerDatePicker: View {
    @ObservedObject var state: AppState
    @PlannerState<Bool> private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 9) {
                Image(systemName: "calendar")
                Text(state.selectedDate.formatted(.dateTime.locale(state.locale).day().month(.wide).year()))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .help(state.text("planDate"))
        .popover(isPresented: $presented) {
            MonthCalendarView(state: state, small: true).frame(width: 340).padding(10)
                .onChange(of: state.selectedDate) { _, _ in presented = false }
        }
    }
}

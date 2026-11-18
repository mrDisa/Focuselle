import SwiftUI

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

struct TasksView: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DatePicker(state.text("planDate"), selection: $state.selectedDate, displayedComponents: .date)
            HStack {
                TextField(state.text("taskTitle"), text: $state.taskDraft).textFieldStyle(.roundedBorder).onSubmit(add)
                Button(state.text("addTask"), action: add).buttonStyle(.borderedProminent).tint(.primary)
                    .disabled(state.taskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.storageReady)
            }
            TaskRows(state: state)
        }
    }
    private func add() {
        state.addTask(title: state.taskDraft)
        if state.storageError == nil { state.taskDraft = "" }
    }
}

struct TaskRows: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.dayTasks.isEmpty {
                Text(state.text("noTasks")).foregroundStyle(.secondary)
            }
            ForEach(state.dayTasks) { task in
                HStack(alignment: .top, spacing: 10) {
                    Button { state.toggleTask(task) } label: {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    }.buttonStyle(.plain).accessibilityLabel(state.text(task.isCompleted ? "markIncomplete" : "markComplete"))
                        .disabled(!state.storageReady)
                    Text(task.title).strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { state.chooseTask(task) } label: { Image(systemName: "arrow.up.right") }
                        .buttonStyle(.plain).help(state.text("focusOnTask"))
                        .accessibilityLabel(state.text("focusOnTask"))
                        .disabled(task.isCompleted || state.timer.isRunning || state.hasProgress || !state.storageReady)
                }
                Divider()
            }
        }
    }
}

struct SessionHistoryView: View {
    @ObservedObject var state: AppState
    private var sessions: [FocusSession] { state.sessions.filter { $0.localDay == state.selectedDay }.reversed() }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DatePicker(state.text("planDate"), selection: $state.selectedDate, displayedComponents: .date)
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

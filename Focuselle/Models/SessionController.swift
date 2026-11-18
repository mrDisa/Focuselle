import Foundation

/// All state transitions are persisted before being exposed to the UI.
final class SessionController {
    private let store: FocusStore
    private(set) var timer: FocusTimer
    private(set) var active: ActiveInterval
    private var lastCheckpoint: TimeInterval = 0
    private(set) var wasRestored = false

    init(store: FocusStore) throws {
        self.store = store
        if let saved = try store.activeInterval() {
            active = saved
            timer = FocusTimer(phase: saved.phase, duration: saved.duration, remaining: saved.remaining)
            wasRestored = saved.startedAt != nil && saved.remaining > 0
        } else {
            timer = FocusTimer()
            active = Self.idle(phase: .focus, work: 25, rest: 5)
        }
    }

    func toggle(now: TimeInterval, date: Date, timeZone: TimeZone = .current) throws {
        guard timer.remaining > 0 else { return }
        var next = timer
        var snapshot = active
        // Refresh before pausing so crossing the deadline still records completion.
        let completed = next.refresh(now: now)
        if !completed { next.toggle(now: now) }
        if snapshot.startedAt == nil {
            snapshot.startedAt = date
            snapshot.localDay = LocalDay.string(date, timeZone: timeZone)
            snapshot.timeZoneID = timeZone.identifier
        }
        snapshot.remaining = next.remaining
        try store.checkpoint(snapshot, session: completed ? session(snapshot, endedAt: date, completed: true) : nil)
        timer = next
        active = snapshot
        lastCheckpoint = now
        wasRestored = false
    }

    @discardableResult
    func refresh(now: TimeInterval, date: Date, forceSave: Bool = false) throws -> Bool {
        var next = timer
        let completed = next.refresh(now: now)
        var snapshot = active
        snapshot.remaining = next.remaining
        if completed || forceSave || (next.isRunning && now - lastCheckpoint >= 5) {
            try store.checkpoint(snapshot, session: snapshot.remaining == 0 ? session(snapshot, endedAt: date, completed: true) : nil)
            lastCheckpoint = now
        }
        timer = next
        active = snapshot
        return completed
    }

    func pause(now: TimeInterval, date: Date) throws {
        if timer.isRunning { try toggle(now: now, date: date) }
        else { _ = try refresh(now: now, date: date, forceSave: true) }
    }

    /// Keep unsaved state in memory and stop accruing time if persistence fails.
    /// The UI offers an explicit retry; it must never reset or replace the database.
    func freezeAfterFailure(now: TimeInterval) {
        _ = timer.refresh(now: now)
        if timer.isRunning { timer.toggle(now: now) }
        active.remaining = timer.remaining
    }

    func reset(now: TimeInterval, date: Date) throws {
        var previous = timer
        let justCompleted = previous.refresh(now: now)
        var snapshot = active
        snapshot.remaining = previous.remaining
        let recorded = snapshot.startedAt != nil && snapshot.duration > snapshot.remaining
            ? session(snapshot, endedAt: date, completed: justCompleted || snapshot.remaining == 0) : nil
        let replacement = Self.idle(phase: snapshot.phase, work: snapshot.workMinutes, rest: snapshot.restMinutes,
                                    taskID: snapshot.taskID, taskTitle: snapshot.taskTitle)
        try store.checkpoint(replacement, session: recorded)
        active = replacement
        timer = FocusTimer(phase: replacement.phase, duration: replacement.duration, remaining: replacement.remaining)
        wasRestored = false
    }

    func select(phase: FocusTimer.Phase, work: Int, rest: Int) throws {
        guard !timer.isRunning, timer.remaining == timer.duration, (1...240).contains(work), (1...120).contains(rest) else { return }
        let replacement = Self.idle(phase: phase, work: work, rest: rest, taskID: active.taskID, taskTitle: active.taskTitle)
        try store.checkpoint(replacement)
        active = replacement
        timer = FocusTimer(phase: phase, duration: replacement.duration, remaining: replacement.remaining)
    }

    func selectTask(_ task: FocusTask?) throws {
        guard !timer.isRunning, timer.remaining == timer.duration else { return }
        var replacement = active
        replacement.taskID = task?.id
        replacement.taskTitle = task?.title
        try store.checkpoint(replacement)
        active = replacement
    }

    private func session(_ snapshot: ActiveInterval, endedAt: Date, completed: Bool) -> FocusSession? {
        guard snapshot.phase == .focus, let startedAt = snapshot.startedAt else { return nil }
        return FocusSession(id: snapshot.id, taskID: snapshot.taskID, taskTitle: snapshot.taskTitle,
                            startedAt: startedAt, endedAt: max(startedAt, endedAt),
                            focusSeconds: snapshot.duration - snapshot.remaining,
                            status: completed ? "completed" : "interrupted", localDay: snapshot.localDay, timeZoneID: snapshot.timeZoneID)
    }

    private static func idle(phase: FocusTimer.Phase, work: Int, rest: Int,
                             taskID: String? = nil, taskTitle: String? = nil) -> ActiveInterval {
        let duration = Double((phase == .focus ? work : (phase == .shortBreak ? rest : 15)) * 60)
        return ActiveInterval(id: UUID().uuidString, phase: phase, duration: duration, remaining: duration,
                              taskID: taskID, taskTitle: taskTitle, localDay: "", timeZoneID: "",
                              workMinutes: work, restMinutes: rest)
    }
}

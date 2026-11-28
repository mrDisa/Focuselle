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
        try reconcileCompletedTask()
    }

    func toggle(now: TimeInterval, date: Date, timeZone: TimeZone = .current, autoAdvance: Bool = false) throws {
        if timer.remaining == 0 && autoAdvance {
            _ = try refresh(now: now, date: date, forceSave: true, autoAdvance: true)
            return
        }
        guard timer.remaining > 0 else { return }
        var next = timer
        var snapshot = active
        // Refresh before pausing so crossing the deadline still records completion.
        let completed = next.refresh(now: now)
        if completed && autoAdvance {
            try advance(from: snapshot, now: now, date: date, timeZone: timeZone)
            return
        }
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
    func refresh(now: TimeInterval, date: Date, forceSave: Bool = false, autoAdvance: Bool = false) throws -> Bool {
        var next = timer
        let completed = next.refresh(now: now)
        var snapshot = active
        snapshot.remaining = next.remaining
        if autoAdvance && snapshot.remaining == 0 && snapshot.startedAt != nil {
            try advance(from: snapshot, now: now, date: date, timeZone: .current)
            return true
        }
        if completed || forceSave || (next.isRunning && now - lastCheckpoint >= 5) {
            try store.checkpoint(snapshot, session: snapshot.remaining == 0 ? session(snapshot, endedAt: date, completed: true) : nil)
            lastCheckpoint = now
        }
        timer = next
        active = snapshot
        return completed
    }

    /// Save the completed focus and the next interval together. Delayed ticks start
    /// one full interval now; they never invent work during the delay.
    private func advance(from previous: ActiveInterval, now: TimeInterval, date: Date, timeZone: TimeZone) throws {
        var finished = previous
        finished.remaining = 0
        let phase: FocusTimer.Phase = previous.phase == .focus ? .shortBreak : .focus
        let (nextID, nextTitle) = try nextTask(after: previous)
        var replacement = Self.idle(phase: phase, work: previous.workMinutes, rest: previous.restMinutes,
                                    taskID: nextID, taskTitle: nextTitle)
        replacement.startedAt = date
        replacement.localDay = LocalDay.string(date, timeZone: timeZone)
        replacement.timeZoneID = timeZone.identifier
        var next = FocusTimer(phase: phase, duration: replacement.duration, remaining: replacement.remaining)
        next.toggle(now: now)
        try store.checkpoint(replacement, session: session(finished, endedAt: date, completed: true))
        active = replacement
        timer = next
        lastCheckpoint = now
        wasRestored = false
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
        let (nextID, nextTitle) = try nextTask(after: snapshot)
        let replacement = Self.idle(phase: snapshot.phase, work: snapshot.workMinutes, rest: snapshot.restMinutes,
                                    taskID: nextID, taskTitle: nextTitle)
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

    private func nextTask(after interval: ActiveInterval) throws -> (String?, String?) {
        guard let id = interval.taskID else { return (nil, nil) }
        let tasks = try store.tasks()
        guard let current = tasks.first(where: { $0.id == id }) else { return (nil, nil) }
        guard current.isCompleted else { return (current.id, current.title) }
        let next = tasks.first { $0.plannedDay == current.plannedDay && !$0.isCompleted }
        return (next?.id, next?.title)
    }

    func reconcileCompletedTask() throws {
        guard !timer.isRunning, timer.remaining == timer.duration else { return }
        let (id, title) = try nextTask(after: active)
        guard id != active.taskID || title != active.taskTitle else { return }
        var replacement = active
        replacement.taskID = id
        replacement.taskTitle = title
        try store.checkpoint(replacement)
        active = replacement
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

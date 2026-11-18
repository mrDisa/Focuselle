import Foundation

@main
struct StorageTests {
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { fatalError(message) }
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FocuselleTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("records.sqlite")
        let day = "2026-11-18"
        var task = FocusTask(title: "План 'дня' 🕰", plannedDay: day)
        let subtask = Subtask(taskID: task.id, title: "Подзадача")
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let block = TimeBlock(taskID: task.id, plannedDay: day, startsAt: instant, endsAt: instant.addingTimeInterval(1800))
        let custom = TimerPreset(id: "custom", focusMinutes: 45, shortBreakMinutes: 8, longBreakMinutes: 20, longBreakFrequency: 3)
        do {
            let store = try FocusStore(url: url)
            try store.saveTask(task)
            try store.saveSubtask(subtask)
            try store.saveTimeBlock(block)
            try store.savePreset(custom)
            task.isCompleted = true
            task.completedAt = instant
            try store.saveTask(task)
            try expect(store.subtasks(taskID: task.id) == [subtask], "Updating parent must preserve children")
        }
        do {
            let store = try FocusStore(url: url)
            try expect(store.tasks(day: day) == [task], "Task did not survive close/reopen")
            try expect(store.subtasks(taskID: task.id) == [subtask], "Subtask did not survive")
            try expect(store.timeBlocks(day: day) == [block], "Time block did not survive")
            try expect(store.presets().contains(custom), "Custom preset did not survive")
            try expect(store.presets().count == 4, "Default presets must seed only once")
            // A v1 database has these tables and data, but not the v2 indexes.
            try store.database.execute("DROP INDEX tasks_day_order")
            try store.database.execute("DROP INDEX sessions_day")
            try store.database.execute("DROP INDEX blocks_day")
            try store.database.execute("PRAGMA user_version = 1")
        }
        do {
            let upgraded = try FocusStore(url: url)
            try expect(upgraded.tasks() == [task], "Migration lost tasks")
            try expect(upgraded.subtasks(taskID: task.id) == [subtask], "Migration lost subtasks")
            try expect(upgraded.timeBlocks(day: day) == [block], "Migration lost blocks")
            try expect(upgraded.presets().contains(custom), "Migration lost presets")
            try expect(upgraded.database.rows("PRAGMA user_version").first?["user_version"]?.number == 2, "Migration not applied")
        }
        print("PASS: records survive reopen, bound Unicode text, parent update, v1→v2 migration")

        let sessionURL = directory.appendingPathComponent("sessions.sqlite")
        let moscow = TimeZone(identifier: "Europe/Moscow")!
        let newYork = TimeZone(identifier: "America/New_York")!
        let midnight = ISO8601DateFormatter().date(from: "2026-11-18T21:30:00Z")!
        var savedID = ""
        do {
            let store = try FocusStore(url: sessionURL)
            try store.saveTask(task)
            let controller = try SessionController(store: store)
            try controller.select(phase: .focus, work: 1, rest: 1)
            try controller.selectTask(task)
            try controller.toggle(now: 100, date: midnight, timeZone: moscow)
            _ = try controller.refresh(now: 110, date: midnight.addingTimeInterval(10))
            savedID = controller.active.id
        }
        do {
            let store = try FocusStore(url: sessionURL)
            let controller = try SessionController(store: store)
            try expect(controller.wasRestored && !controller.timer.isRunning, "Restored timer must pause")
            try expect(controller.timer.remaining == 50, "Checkpoint did not restore")
            try expect(controller.active.localDay == "2026-11-19", "Start-day attribution incorrect")
            try expect(store.sessions().isEmpty, "Unfinished interval must not become a completed session")
            try controller.toggle(now: 9000, date: midnight.addingTimeInterval(10000), timeZone: newYork)
            // Attempted reassignment during focus must leave attribution intact.
            try controller.selectTask(nil)
            try expect(controller.active.taskID == task.id, "Active task was reassigned")
            try expect(controller.refresh(now: 9050, date: midnight.addingTimeInterval(10050)), "Completion missing")
            _ = try controller.refresh(now: 9100, date: midnight.addingTimeInterval(10100), forceSave: true)
            try controller.reset(now: 9100, date: midnight.addingTimeInterval(10100))
            let sessions = try store.sessions()
            try expect(sessions.count == 1 && sessions[0].id == savedID, "Duplicate completion")
            try expect(sessions[0].focusSeconds == 60 && sessions[0].status == "completed", "Downtime counted as focus")
            try expect(sessions[0].localDay == "2026-11-19" && sessions[0].timeZoneID == moscow.identifier, "Timezone changed history")
            try store.deleteTask(id: task.id)
            let retained = try store.sessions()[0]
            try expect(retained.taskID == nil && retained.taskTitle == task.title, "Deleted task lost historical title")
        }
        print("PASS: paused recovery, no downtime, one completion, fixed local day, retained task title")

        do {
            let store = try FocusStore(url: directory.appendingPathComponent("pause.sqlite"))
            let controller = try SessionController(store: store)
            try controller.toggle(now: 10, date: instant)
            try controller.pause(now: 30, date: instant.addingTimeInterval(20))
            try expect(!controller.timer.isRunning && controller.timer.remaining == 1480, "Sleep/quit did not pause")
            try controller.toggle(now: 5000, date: instant.addingTimeInterval(5000))
            try controller.reset(now: 5010, date: instant.addingTimeInterval(5010))
            let sessions = try store.sessions()
            try expect(sessions.count == 1 && sessions[0].focusSeconds == 30 && sessions[0].status == "interrupted", "Reset lost partial focus")
            try controller.reset(now: 6000, date: instant.addingTimeInterval(6000))
            try expect(store.sessions().count == 1, "Repeated reset duplicated partial focus")
            try controller.select(phase: .shortBreak, work: 1, rest: 1)
            try controller.toggle(now: 7000, date: instant)
            _ = try controller.refresh(now: 7060, date: instant.addingTimeInterval(60))
            try expect(store.sessions().count == 1, "Break recorded as focus")
        }
        print("PASS: sleep/quit pause, partial focus on reset, breaks excluded")

        do {
            let store = try FocusStore(url: directory.appendingPathComponent("atomic.sqlite"))
            let controller = try SessionController(store: store)
            try controller.select(phase: .focus, work: 1, rest: 1)
            try controller.toggle(now: 10, date: instant)
            try store.database.execute("CREATE TRIGGER reject_checkpoint BEFORE UPDATE ON active_interval BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END")
            do {
                _ = try controller.refresh(now: 70, date: instant.addingTimeInterval(60))
                fatalError("Write failure not propagated")
            } catch DatabaseError.sqlite { }
            try expect(store.sessions().isEmpty, "Failed transaction left an orphaned completion")
            try expect(store.activeInterval()?.remaining == 60, "Failed transaction changed checkpoint")
            controller.freezeAfterFailure(now: 70)
            try expect(!controller.timer.isRunning, "Storage error must stop accrual")
            try store.database.execute("DROP TRIGGER reject_checkpoint")
            _ = try controller.refresh(now: 7000, date: instant.addingTimeInterval(7000), forceSave: true)
            try expect(store.sessions().count == 1, "Retry did not persist completion")
            try expect(store.sessions()[0].focusSeconds == 60, "Retry counted error downtime")
        }
        print("PASS: atomic completion/checkpoint rollback and retry after storage failure")

        let futureURL = directory.appendingPathComponent("future.sqlite")
        do {
            let store = try FocusStore(url: futureURL)
            try store.saveTask(task)
            try store.database.execute("PRAGMA user_version = 999")
        }
        do {
            _ = try FocusStore(url: futureURL)
            fatalError("Future schema should not open")
        } catch DatabaseError.newerSchema { }
        print("PASS: newer database rejected without destructive reset")
    }
}

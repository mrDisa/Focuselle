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
            try store.database.execute("ALTER TABLE tasks DROP COLUMN details")
            try store.database.execute("PRAGMA user_version = 1")
        }
        do {
            let upgraded = try FocusStore(url: url)
            try expect(upgraded.tasks() == [task], "Migration lost tasks")
            try expect(upgraded.subtasks(taskID: task.id) == [subtask], "Migration lost subtasks")
            try expect(upgraded.timeBlocks(day: day) == [block], "Migration lost blocks")
            try expect(upgraded.presets().contains(custom), "Migration lost presets")
            try expect(upgraded.database.rows("PRAGMA user_version").first?["user_version"]?.number == 3, "Migration not applied")
        }
        print("PASS: records survive reopen, bound Unicode text, parent update, v1→v3 migration")

        do {
            var described = task
            described.title = "Edited task"
            described.details = "Описание с Unicode 📝\nВторая строка"
            let store = try FocusStore(url: url)
            try store.saveTask(described)
            let reopened = try FocusStore(url: url)
            try expect(reopened.tasks().first == described, "Edited title and description did not survive reopen")
            try expect(reopened.subtasks(taskID: task.id) == [subtask], "Editing task description removed subtasks")
        }
        print("PASS: task title and multiline description persist after reopen")

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

        do {
            let store = try FocusStore(url: directory.appendingPathComponent("cycle.sqlite"))
            let task = FocusTask(title: "Unfinished cycle task", plannedDay: day)
            try store.saveTask(task)
            let controller = try SessionController(store: store)
            try controller.select(phase: .focus, work: 1, rest: 2)
            try controller.selectTask(task)
            try controller.toggle(now: 0, date: instant, autoAdvance: true)
            try expect(controller.refresh(now: 65, date: instant.addingTimeInterval(65), autoAdvance: true), "Focus must advance")
            try expect(controller.timer.phase == .shortBreak && controller.timer.isRunning && controller.timer.remaining == 120, "Delayed tick must start a full break")
            try expect(controller.active.taskID == task.id, "Transition lost task")
            try expect(store.sessions().count == 1 && store.sessions()[0].focusSeconds == 60, "Focus completion incorrect")
            try expect(!controller.refresh(now: 65, date: instant.addingTimeInterval(65), autoAdvance: true), "Repeated tick duplicated transition")
            // Completion discovered by a transport action must also advance once.
            try controller.toggle(now: 185, date: instant.addingTimeInterval(185), autoAdvance: true)
            try expect(controller.timer.phase == .focus && controller.timer.isRunning && controller.timer.remaining == 60, "Break must return to work")
            try expect(store.sessions().count == 1, "Break appeared in focus history")
            let restored = try SessionController(store: store)
            try expect(restored.timer.phase == .focus && !restored.timer.isRunning && restored.timer.remaining == 60, "Next interval must restore paused")
            try controller.pause(now: 185, date: instant.addingTimeInterval(185))
            try controller.reset(now: 185, date: instant.addingTimeInterval(185))
            try controller.select(phase: .longBreak, work: 1, rest: 2)
            try controller.toggle(now: 200, date: instant, autoAdvance: true)
            _ = try controller.refresh(now: 1100, date: instant.addingTimeInterval(900), autoAdvance: true)
            try expect(controller.timer.phase == .focus && controller.timer.isRunning, "Long break must return to work")
        }
        print("PASS: automatic work/break cycle, delayed tick, transport completion, task retention, paused recovery")

        do {
            let store = try FocusStore(url: directory.appendingPathComponent("cycle-failure.sqlite"))
            let controller = try SessionController(store: store)
            try controller.select(phase: .focus, work: 1, rest: 1)
            try controller.toggle(now: 0, date: instant)
            try store.database.execute("CREATE TRIGGER reject_transition BEFORE UPDATE ON active_interval BEGIN SELECT RAISE(ABORT, 'simulated failure'); END")
            do {
                _ = try controller.refresh(now: 60, date: instant.addingTimeInterval(60), autoAdvance: true)
                fatalError("Transition failure not propagated")
            } catch DatabaseError.sqlite { }
            try expect(store.sessions().isEmpty && store.activeInterval()?.phase == .focus, "Transition did not roll back atomically")
            controller.freezeAfterFailure(now: 60)
            try store.database.execute("DROP TRIGGER reject_transition")
            _ = try controller.refresh(now: 6000, date: instant.addingTimeInterval(6000), forceSave: true, autoAdvance: true)
            try expect(controller.timer.phase == .shortBreak && controller.timer.remaining == 60 && controller.timer.isRunning, "Retry lost transition or counted downtime")
            _ = try controller.refresh(now: 6000, date: instant.addingTimeInterval(6000), forceSave: true, autoAdvance: true)
            try expect(store.sessions().count == 1, "Retry duplicated completion")
        }
        print("PASS: atomic automatic transition rollback and retry without duplicates or downtime")

        do {
            let store = try FocusStore(url: directory.appendingPathComponent("next-task.sqlite"))
            var first = FocusTask(title: "First", plannedDay: day, sortOrder: 0)
            let next = FocusTask(title: "Next", plannedDay: day, sortOrder: 1)
            let otherDay = FocusTask(title: "Tomorrow", plannedDay: "2026-11-19", sortOrder: -1)
            for task in [first, next, otherDay] { try store.saveTask(task) }
            let controller = try SessionController(store: store)
            try controller.select(phase: .focus, work: 1, rest: 1)
            try controller.selectTask(first)
            try controller.toggle(now: 0, date: instant)
            first.isCompleted = true
            try store.saveTask(first)
            try controller.reconcileCompletedTask()
            try expect(controller.active.taskID == first.id, "Active focus must retain its original task")
            _ = try controller.refresh(now: 60, date: instant.addingTimeInterval(60), autoAdvance: true)
            try expect(controller.active.taskID == next.id, "Completed task must advance within the same day")
            try expect(store.sessions().first?.taskID == first.id, "Task advance must retain historical attribution")
            try controller.pause(now: 60, date: instant.addingTimeInterval(60))
            try store.deleteTask(id: next.id)
            try controller.reconcileCompletedTask()
            try expect(controller.active.taskID == nil, "Deleted idle task must be cleared")
            let restored = try SessionController(store: store)
            try expect(restored.active.taskID == nil, "Cleared task must survive restart")
        }
        print("PASS: completed-task handoff, same-day selection, historical attribution and deleted-task recovery")

        var gridCalendar = Calendar(identifier: .gregorian)
        gridCalendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        for (year, month, expectedDays) in [(2024, 2, 29), (2026, 11, 30), (2026, 3, 31), (2026, 12, 31)] {
            let date = gridCalendar.date(from: DateComponents(year: year, month: month, day: 15))!
            let grid = CalendarMonth.days(containing: date, calendar: gridCalendar)
            try expect(grid.count == 42 && Set(grid).count == 42, "Month grid must contain 42 unique days")
            try expect(gridCalendar.component(.weekday, from: grid[0]) == 2, "Grid must start Monday")
            try expect(gridCalendar.component(.weekday, from: grid[41]) == 1, "Grid must end Sunday")
            try expect(grid.filter { gridCalendar.isDate($0, equalTo: date, toGranularity: .month) }.count == expectedDays,
                       "Month grid lost a day at a leap year, DST or year boundary")
        }
        print("PASS: Monday-first calendar, leap February, DST month and year boundary")

        var insightsCalendar = Calendar(identifier: .gregorian)
        insightsCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = insightsCalendar.date(from: DateComponents(year: 2026, month: 11, day: 22))!
        func sample(_ id: String, day: String, seconds: Double, status: String) -> FocusSession {
            FocusSession(id: id, taskID: "goal", taskTitle: "Goal", startedAt: end, endedAt: end,
                         focusSeconds: seconds, status: status, localDay: day, timeZoneID: "UTC")
        }
        let insights = FocusInsights(sessions: [sample("a", day: "2026-11-22", seconds: 1500, status: "completed"),
                                               sample("b", day: "2026-11-22", seconds: 300, status: "interrupted"),
                                               sample("c", day: "2026-11-16", seconds: 600, status: "completed"),
                                               sample("outside", day: "2026-11-15", seconds: 9999, status: "completed")],
                                     endingAt: end, count: 7, calendar: insightsCalendar)
        try expect(insights.days.count == 7 && insights.days.first?.day == "2026-11-16", "Insights range boundary incorrect")
        try expect(insights.totalSeconds == 2400 && insights.completedCount == 2 && insights.activeDays == 2, "Insights totals incorrect")
        try expect(insights.days.last?.interruptedSeconds == 300 && insights.tasks.first?.seconds == 2400, "Partial focus or task grouping incorrect")
        let empty = FocusInsights(sessions: [], endingAt: end, count: 30, calendar: insightsCalendar)
        try expect(empty.days.count == 30 && empty.totalSeconds == 0 && empty.tasks.isEmpty, "Empty insights must include zero days")
        print("PASS: insights range, partial focus, zero days, completion count and task totals")

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

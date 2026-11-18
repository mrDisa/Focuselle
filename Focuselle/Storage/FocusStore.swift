import Foundation

final class FocusStore {
    let database: Database
    init(url: URL) throws { database = try Database(url: url) }

    static func defaultURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("Focuselle", isDirectory: true).appendingPathComponent("focuselle.sqlite")
    }

    func saveTask(_ task: FocusTask) throws {
        try database.execute("""
            INSERT INTO tasks VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET title=excluded.title, planned_day=excluded.planned_day,
            estimate=excluded.estimate, completed=excluded.completed, completed_at=excluded.completed_at, sort_order=excluded.sort_order
            """, [.text(task.id), .text(task.title), .text(task.plannedDay), .number(Double(task.estimate)),
                  .number(task.isCompleted ? 1 : 0), .date(task.completedAt), .number(Double(task.sortOrder))])
    }

    func tasks(day: String? = nil) throws -> [FocusTask] {
        let rows = try database.rows("SELECT * FROM tasks" + (day == nil ? "" : " WHERE planned_day = ?") + " ORDER BY sort_order, id",
                                     day.map { [.text($0)] } ?? [])
        return try rows.map { row in
            FocusTask(id: try row.string("id"), title: try row.string("title"), plannedDay: try row.string("planned_day"),
                      estimate: Int(try row.double("estimate")), isCompleted: try row.double("completed") == 1,
                      completedAt: row["completed_at"]?.number.map(Date.init(timeIntervalSince1970:)),
                      sortOrder: Int(try row.double("sort_order")))
        }
    }

    func deleteTask(id: String) throws {
        try database.execute("DELETE FROM tasks WHERE id = ?", [.text(id)])
    }

    func saveSubtask(_ subtask: Subtask) throws {
        try database.execute("""
            INSERT INTO subtasks VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET
            task_id=excluded.task_id, title=excluded.title, completed=excluded.completed, sort_order=excluded.sort_order
            """, [.text(subtask.id), .text(subtask.taskID), .text(subtask.title),
                  .number(subtask.isCompleted ? 1 : 0), .number(Double(subtask.sortOrder))])
    }

    func subtasks(taskID: String) throws -> [Subtask] {
        try database.rows("SELECT * FROM subtasks WHERE task_id = ? ORDER BY sort_order, id", [.text(taskID)]).map { row in
            Subtask(id: try row.string("id"), taskID: try row.string("task_id"), title: try row.string("title"),
                    isCompleted: try row.double("completed") == 1, sortOrder: Int(try row.double("sort_order")))
        }
    }

    func saveTimeBlock(_ block: TimeBlock) throws {
        try database.execute("""
            INSERT INTO time_blocks VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET
            task_id=excluded.task_id, planned_day=excluded.planned_day, starts_at=excluded.starts_at, ends_at=excluded.ends_at
            """, [.text(block.id), .optional(block.taskID), .text(block.plannedDay), .date(block.startsAt), .date(block.endsAt)])
    }

    func timeBlocks(day: String) throws -> [TimeBlock] {
        try database.rows("SELECT * FROM time_blocks WHERE planned_day = ? ORDER BY starts_at", [.text(day)]).map { row in
            TimeBlock(id: try row.string("id"), taskID: row["task_id"]?.text, plannedDay: try row.string("planned_day"),
                      startsAt: Date(timeIntervalSince1970: try row.double("starts_at")),
                      endsAt: Date(timeIntervalSince1970: try row.double("ends_at")))
        }
    }

    func savePreset(_ preset: TimerPreset) throws {
        try database.execute("""
            INSERT INTO presets VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET
            focus_minutes=excluded.focus_minutes, short_break=excluded.short_break, long_break=excluded.long_break,
            long_frequency=excluded.long_frequency, pinned=excluded.pinned
            """, [.text(preset.id), .number(Double(preset.focusMinutes)), .number(Double(preset.shortBreakMinutes)),
                  .number(Double(preset.longBreakMinutes)), .number(Double(preset.longBreakFrequency)), .number(preset.isPinned ? 1 : 0)])
    }

    func presets() throws -> [TimerPreset] {
        try database.rows("SELECT * FROM presets ORDER BY focus_minutes, id").map { row in
            TimerPreset(id: try row.string("id"), focusMinutes: Int(try row.double("focus_minutes")),
                        shortBreakMinutes: Int(try row.double("short_break")), longBreakMinutes: Int(try row.double("long_break")),
                        longBreakFrequency: Int(try row.double("long_frequency")), isPinned: try row.double("pinned") == 1)
        }
    }

    func activeInterval() throws -> ActiveInterval? {
        guard let payload = try database.rows("SELECT payload FROM active_interval WHERE singleton = 1").first?["payload"]?.text else { return nil }
        let active = try JSONDecoder().decode(ActiveInterval.self, from: Data(payload.utf8))
        guard active.duration.isFinite, active.remaining.isFinite, active.duration > 0,
              active.remaining >= 0, active.remaining <= active.duration,
              (1...240).contains(active.workMinutes), (1...120).contains(active.restMinutes) else { throw DatabaseError.invalidData }
        return active
    }

    /// Session insertion and checkpoint replacement commit together. A session UUID
    /// makes retries idempotent, including a retry after an uncertain commit result.
    func checkpoint(_ active: ActiveInterval, session: FocusSession? = nil) throws {
        let payload = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
        try database.transaction {
            if let session {
                // A task may have been removed after the interval began. Keep its title snapshot.
                let taskID = try session.taskID.flatMap { id in
                    try database.rows("SELECT id FROM tasks WHERE id = ?", [.text(id)]).first?["id"]?.text
                }
                try database.execute("""
                    INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO NOTHING
                    """, [.text(session.id), .optional(taskID), .optional(session.taskTitle), .date(session.startedAt),
                          .date(session.endedAt), .number(session.focusSeconds), .text(session.status),
                          .text(session.localDay), .text(session.timeZoneID)])
            }
            try database.execute("""
                INSERT INTO active_interval VALUES (1, ?) ON CONFLICT(singleton) DO UPDATE SET payload=excluded.payload
                """, [.text(payload)])
        }
    }

    func sessions(day: String? = nil) throws -> [FocusSession] {
        try database.rows("SELECT * FROM sessions" + (day == nil ? "" : " WHERE local_day = ?") + " ORDER BY started_at, id",
                          day.map { [.text($0)] } ?? []).map { row in
            FocusSession(id: try row.string("id"), taskID: row["task_id"]?.text, taskTitle: row["task_title"]?.text,
                         startedAt: Date(timeIntervalSince1970: try row.double("started_at")),
                         endedAt: Date(timeIntervalSince1970: try row.double("ended_at")), focusSeconds: try row.double("focus_seconds"),
                         status: try row.string("status"), localDay: try row.string("local_day"), timeZoneID: try row.string("time_zone"))
        }
    }
}

private extension Dictionary where Key == String, Value == SQLValue {
    func string(_ key: String) throws -> String {
        guard let value = self[key]?.text else { throw DatabaseError.invalidData }; return value
    }
    func double(_ key: String) throws -> Double {
        guard let value = self[key]?.number else { throw DatabaseError.invalidData }; return value
    }
}

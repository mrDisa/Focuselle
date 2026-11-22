import Foundation
import SQLite3

enum DatabaseError: LocalizedError {
    case sqlite(String)
    case invalidData
    case newerSchema
    var errorDescription: String? {
        switch self {
        case .sqlite(let message): return message
        case .invalidData: return "Invalid stored data"
        case .newerSchema: return "This database was created by a newer version of Focuselle"
        }
    }
}

enum SQLValue {
    case text(String), number(Double), null
    static func optional(_ text: String?) -> SQLValue { text.map(Self.text) ?? .null }
    static func date(_ date: Date?) -> SQLValue { date.map { .number($0.timeIntervalSince1970) } ?? .null }
}

/// Confined to the caller's thread (the main actor in the application).
final class Database {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
            sqlite3_close(handle)
            handle = nil
            throw DatabaseError.sqlite(message)
        }
        do {
            sqlite3_busy_timeout(handle, 3000)
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = FULL")
            try migrate()
        } catch {
            sqlite3_close(handle)
            handle = nil
            throw error
        }
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String, _ values: [SQLValue] = []) throws {
        _ = try rows(sql, values)
    }

    func rows(_ sql: String, _ values: [SQLValue] = []) throws -> [[String: SQLValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw failure()
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text): result = sqlite3_bind_text(statement, index, text, -1, transient)
            case .number(let number): result = sqlite3_bind_double(statement, index, number)
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw failure() }
        }
        var output: [[String: SQLValue]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return output }
            guard result == SQLITE_ROW else { throw failure() }
            var row: [String: SQLValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_NULL: row[name] = .null
                case SQLITE_TEXT: row[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                default: row[name] = .number(sqlite3_column_double(statement, index))
                }
            }
            output.append(row)
        }
    }

    func transaction<T>(_ action: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try action()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func failure() -> DatabaseError { .sqlite(String(cString: sqlite3_errmsg(handle))) }

    private func migrate() throws {
        let version = Int(try rows("PRAGMA user_version").first?["user_version"]?.number ?? 0)
        guard version <= 3 else { throw DatabaseError.newerSchema }
        if version < 1 {
            try transaction {
                try execute("""
                    CREATE TABLE tasks (
                        id TEXT PRIMARY KEY, title TEXT NOT NULL CHECK(length(trim(title)) > 0),
                        planned_day TEXT NOT NULL, estimate INTEGER NOT NULL CHECK(estimate > 0),
                        completed INTEGER NOT NULL CHECK(completed IN (0,1)), completed_at REAL, sort_order INTEGER NOT NULL
                    )
                    """)
                try execute("""
                    CREATE TABLE subtasks (
                        id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
                        title TEXT NOT NULL CHECK(length(trim(title)) > 0), completed INTEGER NOT NULL CHECK(completed IN (0,1)),
                        sort_order INTEGER NOT NULL
                    )
                    """)
                try execute("""
                    CREATE TABLE sessions (
                        id TEXT PRIMARY KEY, task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL, task_title TEXT,
                        started_at REAL NOT NULL, ended_at REAL NOT NULL,
                        focus_seconds REAL NOT NULL CHECK(focus_seconds >= 0),
                        status TEXT NOT NULL CHECK(status IN ('completed','interrupted')),
                        local_day TEXT NOT NULL, time_zone TEXT NOT NULL
                    )
                    """)
                try execute("""
                    CREATE TABLE time_blocks (
                        id TEXT PRIMARY KEY, task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
                        planned_day TEXT NOT NULL, starts_at REAL NOT NULL, ends_at REAL NOT NULL CHECK(ends_at > starts_at)
                    )
                    """)
                try execute("""
                    CREATE TABLE presets (
                        id TEXT PRIMARY KEY, focus_minutes INTEGER NOT NULL CHECK(focus_minutes > 0),
                        short_break INTEGER NOT NULL CHECK(short_break > 0), long_break INTEGER NOT NULL CHECK(long_break > 0),
                        long_frequency INTEGER NOT NULL CHECK(long_frequency > 0), pinned INTEGER NOT NULL CHECK(pinned IN (0,1))
                    )
                    """)
                try execute("CREATE TABLE active_interval (singleton INTEGER PRIMARY KEY CHECK(singleton = 1), payload TEXT NOT NULL)")
                for (id, work, rest) in [("classic",25,5),("deep",50,10),("extended",90,10)] {
                    try execute("INSERT INTO presets VALUES (?, ?, ?, 15, 4, 1)", [.text(id), .number(Double(work)), .number(Double(rest))])
                }
                try execute("PRAGMA user_version = 1")
            }
        }
        if version < 2 {
            try transaction {
                try execute("CREATE INDEX tasks_day_order ON tasks(planned_day, sort_order)")
                try execute("CREATE INDEX sessions_day ON sessions(local_day)")
                try execute("CREATE INDEX blocks_day ON time_blocks(planned_day, starts_at)")
                try execute("PRAGMA user_version = 2")
            }
        }
        if version < 3 {
            try transaction {
                try execute("ALTER TABLE tasks ADD COLUMN details TEXT NOT NULL DEFAULT ''")
                try execute("PRAGMA user_version = 3")
            }
        }

    }
}

extension SQLValue {
    var text: String? { if case .text(let value) = self { return value }; return nil }
    var number: Double? { if case .number(let value) = self { return value }; return nil }
}

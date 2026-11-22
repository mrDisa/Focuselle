import Foundation

struct FocusTask: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var plannedDay: String
    var estimate = 1
    var isCompleted = false
    var completedAt: Date?
    var sortOrder = 0
    var details = ""
}

struct Subtask: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var taskID: String
    var title: String
    var isCompleted = false
    var sortOrder = 0
}

struct TimeBlock: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var taskID: String?
    var plannedDay: String
    var startsAt: Date
    var endsAt: Date
}

struct TimerPreset: Codable, Identifiable, Equatable {
    var id: String
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes = 15
    var longBreakFrequency = 4
    var isPinned = true
}

struct FocusSession: Codable, Identifiable, Equatable {
    var id: String
    var taskID: String?
    var taskTitle: String?
    var startedAt: Date
    var endedAt: Date
    var focusSeconds: Double
    var status: String
    var localDay: String
    var timeZoneID: String
}

/// Wall-clock instants are UTC epoch seconds in SQLite. A local day is deliberately
/// stored separately so a timezone change doesn't move a task or historical session.
enum LocalDay {
    static func string(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct ActiveInterval: Codable, Equatable {
    var id: String
    var phase: FocusTimer.Phase
    var duration: Double
    var remaining: Double
    var startedAt: Date?
    var taskID: String?
    var taskTitle: String?
    var localDay: String
    var timeZoneID: String
    var workMinutes: Int
    var restMinutes: Int
}

/// A stable Monday-first, six-week grid, including dates in neighbouring months.
enum CalendarMonth {
    static func days(containing date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> [Date] {
        guard let start = calendar.dateInterval(of: .month, for: date)?.start else { return [] }
        let offset = (calendar.component(.weekday, from: start) + 5) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: start) }
    }
}

struct FocusDayMetric: Identifiable {
    var date: Date
    var day: String
    var completedSeconds: Double
    var interruptedSeconds: Double
    var id: String { day }
    var totalSeconds: Double { completedSeconds + interruptedSeconds }
}

struct FocusTaskMetric: Identifiable {
    var id: String
    var title: String?
    var seconds: Double
}

struct FocusInsights {
    var days: [FocusDayMetric]
    var sessions: [FocusSession]
    var totalSeconds: Double { days.reduce(0) { $0 + $1.totalSeconds } }
    var completedCount: Int { sessions.filter { $0.status == "completed" }.count }
    var activeDays: Int { days.filter { $0.totalSeconds > 0 }.count }
    var tasks: [FocusTaskMetric] {
        Dictionary(grouping: sessions) { $0.taskID.map { "id:" + $0 } ?? "title:" + ($0.taskTitle ?? "") }
            .map { key, values in FocusTaskMetric(id: key, title: values.last?.taskTitle, seconds: values.reduce(0) { $0 + $1.focusSeconds }) }
            .sorted { $0.seconds == $1.seconds ? $0.id < $1.id : $0.seconds > $1.seconds }
    }

    init(sessions: [FocusSession], endingAt date: Date, count: Int, calendar: Calendar = .current) {
        let end = calendar.startOfDay(for: date)
        let dates = (0..<max(1, count)).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: end) }
        let keys = Set(dates.map { LocalDay.string($0, timeZone: calendar.timeZone) })
        self.sessions = sessions.filter { keys.contains($0.localDay) }
        let grouped = Dictionary(grouping: self.sessions, by: \.localDay)
        days = dates.map { date in
            let key = LocalDay.string(date, timeZone: calendar.timeZone)
            let entries = grouped[key] ?? []
            return FocusDayMetric(date: date, day: key,
                                  completedSeconds: entries.filter { $0.status == "completed" }.reduce(0) { $0 + $1.focusSeconds },
                                  interruptedSeconds: entries.filter { $0.status == "interrupted" }.reduce(0) { $0 + $1.focusSeconds })
        }
    }
}

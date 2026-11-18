import Foundation

struct FocusTask: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var plannedDay: String
    var estimate = 1
    var isCompleted = false
    var completedAt: Date?
    var sortOrder = 0
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

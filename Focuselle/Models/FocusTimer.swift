import Foundation

/// The display tick is only a refresh signal. A monotonic clock measures active work.
struct FocusTimer {
    enum Phase: String, Codable { case focus, shortBreak, longBreak }
    private(set) var phase: Phase = .focus
    private(set) var duration: TimeInterval = 25 * 60
    private(set) var remaining: TimeInterval = 25 * 60
    private(set) var isRunning = false
    private var deadline: TimeInterval?

    init() {}

    /// A restored timer never counts time spent without the process running.
    init(phase: Phase, duration: Double, remaining: Double) {
        self.phase = phase
        self.duration = duration
        self.remaining = remaining
    }

    mutating func toggle(now: TimeInterval) {
        if isRunning {
            _ = refresh(now: now)
            isRunning = false
            deadline = nil
        } else if remaining > 0 {
            deadline = now + remaining
            isRunning = true
        }
    }

    @discardableResult
    mutating func refresh(now: TimeInterval) -> Bool {
        guard isRunning, let deadline else { return false }
        remaining = max(0, deadline - now)
        guard remaining == 0 else { return false }
        isRunning = false
        self.deadline = nil
        return true
    }

    mutating func reset() {
        remaining = duration
        deadline = nil
        isRunning = false
    }

    mutating func select(_ phase: Phase, minutes: Int) {
        self.phase = phase
        duration = TimeInterval(max(1, minutes) * 60)
        reset()
    }
}

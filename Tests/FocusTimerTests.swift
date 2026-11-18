import Foundation

@main
struct FocusTimerTests {
    static func main() {
        var timer = FocusTimer()
        timer.toggle(now: 100)
        precondition(!timer.refresh(now: 160))
        precondition(timer.remaining == 1440)
        timer.toggle(now: 170)
        precondition(!timer.isRunning && timer.remaining == 1430)
        _ = timer.refresh(now: 5000)
        precondition(timer.remaining == 1430, "Paused time must not count")
        timer.toggle(now: 5000)
        precondition(timer.refresh(now: 6430))
        precondition(!timer.refresh(now: 6500), "Completion must fire only once")
        precondition(!timer.isRunning && timer.remaining == 0)
        timer.reset()
        precondition(timer.remaining == 1500)
        timer.select(.shortBreak, minutes: 5)
        precondition(timer.duration == 300 && timer.remaining == 300)
        timer.toggle(now: 7000)
        timer.reset()
        precondition(!timer.isRunning && !timer.refresh(now: 9000))
        print("Passed: pause/resume, delayed refresh, one completion, reset and phase selection")
    }
}

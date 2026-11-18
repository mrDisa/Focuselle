import AppKit
import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case focus, tasks, calendar, statistics, sounds, settings
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .focus: "timer"
        case .tasks: "checklist"
        case .calendar: "calendar"
        case .statistics: "chart.bar"
        case .sounds: "headphones"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum Theme: String, CaseIterable { case system, light, dark
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var screen: Screen = .focus
    @Published var timer = FocusTimer()
    @Published var showPlan: Bool { didSet { defaults.set(showPlan, forKey: "showPlan") } }
    @Published var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
    @Published var workMinutes = 25
    @Published var restMinutes = 5
    @Published var selectedDate = Date()
    private let defaults: UserDefaults
    private var ticker: Timer?
    private var sleepObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "system") ?? .system
        language = defaults.string(forKey: "language") ?? (Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en")
        showPlan = defaults.object(forKey: "showPlan") as? Bool ?? true
        ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.timer.isRunning else { return }
                self.toggleTimer()
            }
        }
    }

    var locale: Locale { Locale(identifier: language) }
    var digits: String {
        let seconds = Int(ceil(timer.remaining))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var phaseTitle: String {
        switch timer.phase { case .focus: "focus"; case .shortBreak: "shortBreak"; case .longBreak: "longBreak" }
    }
    var progress: Double { timer.remaining / timer.duration }
    var hasProgress: Bool { timer.remaining < timer.duration }
    var transportTitle: String { timer.isRunning ? "pause" : (hasProgress ? "resume" : "start") }

    func text(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    func toggleTimer() { timer.toggle(now: ProcessInfo.processInfo.systemUptime) }
    func resetTimer() { timer.reset() }
    func selectPhase(_ phase: FocusTimer.Phase) {
        timer.select(phase, minutes: phase == .focus ? workMinutes : (phase == .shortBreak ? restMinutes : 15))
    }
    func selectPreset(work: Int, rest: Int) {
        workMinutes = work
        restMinutes = rest
        selectPhase(.focus)
    }
    private func tick() {
        guard timer.isRunning else { return }
        if timer.refresh(now: ProcessInfo.processInfo.systemUptime) { NSSound.beep() }
    }
}

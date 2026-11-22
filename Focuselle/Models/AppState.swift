import AppKit
import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case focus, tasks, statistics, sounds, settings
    var id: String { rawValue }
    var titleKey: String { self == .tasks ? "planner" : rawValue }
    var shortcutNumber: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
    var symbol: String {
        switch self {
        case .focus: "timer"
        case .tasks: "calendar"
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
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "soundEnabled") } }
    @Published var autoAdvance: Bool { didSet { defaults.set(autoAdvance, forKey: "autoAdvance") } }
    @Published var workMinutes = 25
    @Published var restMinutes = 5
    @Published var selectedDate = Date()
    @Published var taskDraft = ""
    @Published var editingTask: FocusTask?
    @Published private(set) var commandHeld = false
    @Published private(set) var tasks: [FocusTask] = []
    @Published private(set) var sessions: [FocusSession] = []
    @Published private(set) var presets: [TimerPreset] = []
    @Published private(set) var storageError: String?
    @Published private(set) var restoredSession = false
    @Published private(set) var currentTaskTitle: String?
    private let resourceBundle: Bundle
    private let databaseURL: URL?
    private let defaults: UserDefaults
    private var store: FocusStore?
    private var controller: SessionController?
    private var ticker: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var modifierMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var transitionSound: NSSound?

    init(defaults: UserDefaults = .standard, storageURL: URL? = nil, resourceBundle: Bundle = .main) {
        self.resourceBundle = resourceBundle
        self.databaseURL = storageURL
        self.defaults = defaults
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        autoAdvance = defaults.object(forKey: "autoAdvance") as? Bool ?? true
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "system") ?? .system
        language = defaults.string(forKey: "language") ?? (Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en")
        showPlan = defaults.object(forKey: "showPlan") as? Bool ?? true
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.commandHeld = event.modifierFlags.contains(.command) }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.commandHeld = false }
        }
        openStorage()
        ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pauseAndSave()
            }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.pauseAndSave() } }
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
        guard let path = resourceBundle.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    var selectedDay: String { LocalDay.string(selectedDate) }
    var dayTasks: [FocusTask] { tasks.filter { $0.plannedDay == selectedDay } }
    var storageReady: Bool { controller != nil && storageError == nil }

    func toggleTimer() {
        guard storageReady else { return }
        perform {
            let previousPhase = controller?.timer.phase
            try controller?.toggle(now: ProcessInfo.processInfo.systemUptime, date: Date(), autoAdvance: autoAdvance)
            if previousPhase != controller?.timer.phase || controller?.timer.remaining == 0 {
                playTransitionSound()
                try reload()
            }
        }
    }
    func resetTimer() {
        guard storageReady else { return }
        perform { try controller?.reset(now: ProcessInfo.processInfo.systemUptime, date: Date()); try reload() }
    }
    func selectPhase(_ phase: FocusTimer.Phase) {
        guard storageReady else { return }
        perform { try controller?.select(phase: phase, work: workMinutes, rest: restMinutes) }
    }
    func selectPreset(work: Int, rest: Int) {
        guard storageReady else { return }
        perform { try controller?.select(phase: .focus, work: work, rest: rest) }
    }
    private func tick() {
        guard timer.isRunning, storageReady else { return }
        perform {
            if try controller?.refresh(now: ProcessInfo.processInfo.systemUptime, date: Date(), autoAdvance: autoAdvance) == true {
                playTransitionSound()
                try reload()
            }
        }
    }

    func previewTransitionSound(for phase: FocusTimer.Phase) {
        transitionSound?.stop()
        transitionSound = NSSound(named: NSSound.Name(phase == .focus ? "Glass" : "Ping"))
        if let transitionSound { transitionSound.play() } else { NSSound.beep() }
    }

    private func playTransitionSound() {
        guard soundEnabled, let phase = controller?.timer.phase else { return }
        let destination: FocusTimer.Phase = autoAdvance ? phase : (phase == .focus ? .shortBreak : .focus)
        previewTransitionSound(for: destination)
    }

    func addTask(title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, storageReady else { return }
        perform {
            try store?.saveTask(FocusTask(title: cleaned, plannedDay: selectedDay, sortOrder: tasks.count))
            try reload()
        }
    }

    @discardableResult
    func saveTask(_ task: FocusTask) -> Bool {
        guard storageReady else { return false }
        var updated = task
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.title.isEmpty else { return false }
        perform { try store?.saveTask(updated); try reload() }
        return storageError == nil
    }

    func deleteTask(_ task: FocusTask) {
        guard storageReady else { return }
        perform { try store?.deleteTask(id: task.id); try reload() }
    }

    func newTask() {
        editingTask = FocusTask(title: "", plannedDay: selectedDay, sortOrder: tasks.count)
    }

    func toggleTask(_ task: FocusTask) {
        guard storageReady else { return }
        perform {
            var updated = task
            updated.isCompleted.toggle()
            updated.completedAt = updated.isCompleted ? Date() : nil
            try store?.saveTask(updated)
            try reload()
        }
    }

    func chooseTask(_ task: FocusTask?) {
        guard storageReady else { return }
        perform { try controller?.selectTask(task); screen = .focus }
    }

    func retryStorage() {
        if controller == nil { openStorage(); return }
        perform {
            if try controller?.refresh(now: ProcessInfo.processInfo.systemUptime, date: Date(), forceSave: true, autoAdvance: autoAdvance) == true {
                playTransitionSound()
            }
            try reload()
        }
    }

    private func pauseAndSave() {
        guard controller != nil else { return }
        perform { try controller?.pause(now: ProcessInfo.processInfo.systemUptime, date: Date()) }
    }

    private func openStorage() {
        perform {
            let opened = try FocusStore(url: databaseURL ?? FocusStore.defaultURL())
            let restored = try SessionController(store: opened)
            store = opened
            controller = restored
            try reload()
        }
    }

    private func reload() throws {
        tasks = try store?.tasks() ?? []
        sessions = try store?.sessions() ?? []
        presets = try store?.presets() ?? []
    }

    private func sync() {
        guard let controller else { return }
        timer = controller.timer
        workMinutes = controller.active.workMinutes
        restMinutes = controller.active.restMinutes
        restoredSession = controller.wasRestored
        currentTaskTitle = tasks.first { $0.id == controller.active.taskID }?.title ?? controller.active.taskTitle
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            storageError = nil
        } catch {
            controller?.freezeAfterFailure(now: ProcessInfo.processInfo.systemUptime)
            storageError = error.localizedDescription
        }
        sync()
    }
}

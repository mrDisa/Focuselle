import AppKit
import Combine
import Sparkle

// Keep discovery separate from presentation so checking never depends on Settings.
enum UpdateEvent {
    case canCheck(Bool)
    case found(version: String, build: String)
    case notFound
    case finished
}

@MainActor
protocol UpdateBackend: AnyObject {
    var canCheck: Bool { get }
    var isBusy: Bool { get }
    var automaticallyChecks: Bool { get }
    func start(_ receive: @escaping (UpdateEvent) -> Void)
    func probe()
    func present()
}

@MainActor
final class UpdateController: ObservableObject {
    static let backgroundInterval: TimeInterval = 5 * 60
    @Published private(set) var availableVersion: String?
    @Published private(set) var canCheckForUpdates = false
    private let backend: UpdateBackend
    private let defaults: UserDefaults
    private let installedBuild: String
    private let now: () -> Date
    private let automaticallyMonitor: Bool
    private var started = false
    private var lastAttempt: Date?
    private var pendingBackground = false
    private var pendingUserCheck = false
    private var pollTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var wakeCenter: NotificationCenter?
    private static let versionKey = "updates.availableVersion"
    private static let buildKey = "updates.availableBuild"

    init(backend: UpdateBackend? = nil, defaults: UserDefaults = .standard,
         installedBuild: String? = nil, now: @escaping () -> Date = Date.init,
         automaticallyMonitor: Bool = true) {
        self.backend = backend ?? SparkleUpdateBackend()
        self.defaults = defaults
        self.installedBuild = installedBuild ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        self.now = now
        self.automaticallyMonitor = automaticallyMonitor
        if let build = defaults.string(forKey: Self.buildKey),
           let version = defaults.string(forKey: Self.versionKey), !version.isEmpty,
           SUStandardVersionComparator.default.compareVersion(build, toVersion: self.installedBuild) == .orderedDescending {
            availableVersion = version
        } else {
            defaults.removeObject(forKey: Self.versionKey)
            defaults.removeObject(forKey: Self.buildKey)
        }
    }

    deinit {
        pollTimer?.invalidate()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let wakeObserver { wakeCenter?.removeObserver(wakeObserver) }
    }

    func start() { start(performInitialCheck: true) }

    private func start(performInitialCheck: Bool) {
        guard !started else { return }
        started = true
        backend.start { [weak self] event in self?.receive(event) }
        canCheckForUpdates = backend.canCheck
        if automaticallyMonitor {
            let timer = Timer(timeInterval: Self.backgroundInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkInBackground() }
            }
            timer.tolerance = 15
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkInBackground() }
            }
            let center = NSWorkspace.shared.notificationCenter
            wakeCenter = center
            wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkInBackground() }
            }
        }
        if performInitialCheck { checkInBackground() }
    }

    func checkInBackground() {
        guard started else { start(); return }
        guard backend.automaticallyChecks else { return }
        if let lastAttempt {
            let elapsed = now().timeIntervalSince(lastAttempt)
            guard elapsed < 0 || elapsed >= Self.backgroundInterval else { return }
        }
        pendingBackground = true
        drainPendingChecks()
    }

    func checkForUpdates() {
        start(performInitialCheck: false)
        pendingUserCheck = true
        drainPendingChecks()
    }

    private func drainPendingChecks() {
        guard backend.canCheck else { return }
        if pendingUserCheck {
            pendingUserCheck = false
            pendingBackground = false
            lastAttempt = now()
            backend.present()
        } else if pendingBackground && !backend.isBusy {
            pendingBackground = false
            lastAttempt = now()
            // Information checks call the discovery delegates without showing an alert.
            backend.probe()
        }
    }

    private func receive(_ event: UpdateEvent) {
        switch event {
        case .canCheck(let value):
            canCheckForUpdates = value
            drainPendingChecks()
        case .found(let version, let build):
            guard SUStandardVersionComparator.default.compareVersion(build, toVersion: installedBuild) == .orderedDescending else {
                clearAvailableUpdate()
                return
            }
            availableVersion = version
            defaults.set(version, forKey: Self.versionKey)
            defaults.set(build, forKey: Self.buildKey)
        case .notFound:
            clearAvailableUpdate()
        case .finished:
            // Dismissing a dialog or losing the network must not erase a known update.
            drainPendingChecks()
        }
    }

    private func clearAvailableUpdate() {
        availableVersion = nil
        defaults.removeObject(forKey: Self.versionKey)
        defaults.removeObject(forKey: Self.buildKey)
    }
}

@MainActor
final class SparkleUpdateBackend: NSObject, UpdateBackend, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private let bundle: Bundle
    private var updater: SPUUpdater?
    private var receive: ((UpdateEvent) -> Void)?
    private var observation: AnyCancellable?
    var canCheck: Bool { updater?.canCheckForUpdates ?? false }
    var isBusy: Bool { updater?.sessionInProgress ?? false }
    var automaticallyChecks: Bool { updater?.automaticallyChecksForUpdates ?? false }

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        super.init()
    }

    func start(_ receive: @escaping (UpdateEvent) -> Void) {
        guard updater == nil else { return }
        self.receive = receive
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: self)
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: self)
        self.updater = updater
        observation = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.receive?(.canCheck(value)) }
        do { try updater.start() }
        catch {
            NSLog("Focuselle updater could not start: %@", error.localizedDescription)
            receive(.canCheck(false))
        }
    }

    func probe() { updater?.checkForUpdateInformation() }
    func present() { updater?.checkForUpdates() }
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool { false }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        receive?(.found(version: update.displayVersionString, build: update.versionString))
    }
    func standardUserDriverWillFinishUpdateSession() { receive?(.finished) }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        receive?(.found(version: item.displayVersionString, build: item.versionString))
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { receive?(.notFound) }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        receive?(.finished)
    }
}

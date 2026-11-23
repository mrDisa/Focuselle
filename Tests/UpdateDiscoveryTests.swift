import AppKit
import Foundation

@MainActor
private final class TestBackend: UpdateBackend {
    var canCheck = true
    var isBusy = false
    var automaticallyChecks = true
    var probes = 0
    var presentations = 0
    var starts = 0
    private var receive: ((UpdateEvent) -> Void)?
    func start(_ receive: @escaping (UpdateEvent) -> Void) {
        starts += 1
        self.receive = receive
        receive(.canCheck(canCheck))
    }
    func probe() {
        precondition(!isBusy, "No concurrent update sessions")
        probes += 1
        isBusy = true
        canCheck = false
        receive?(.canCheck(false))
    }
    func present() { presentations += 1 }
    func found(_ version: String, build: String) { receive?(.found(version: version, build: build)) }
    func notFound() { receive?(.notFound) }
    func finish() {
        isBusy = false
        canCheck = true
        receive?(.canCheck(true))
        receive?(.finished)
    }
}

@main
struct UpdateDiscoveryTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "dev.focuselle.updates.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var clock = Date(timeIntervalSince1970: 1_000)
        let backend = TestBackend()
        let updates = UpdateController(backend: backend, defaults: defaults, installedBuild: "4", now: { clock }, automaticallyMonitor: false)
        updates.start()
        precondition(backend.starts == 1 && backend.probes == 1 && backend.presentations == 0,
                     "Discover immediately at launch without opening Settings or a dialog")
        backend.found("0.4.1", build: "5")
        precondition(updates.availableVersion == "0.4.1", "Publish the sidebar badge immediately")
        backend.finish()
        precondition(updates.availableVersion == "0.4.1", "Finishing a silent probe retains the badge")
        updates.start()
        updates.checkInBackground()
        precondition(backend.starts == 1 && backend.probes == 1, "Do not recheck on every view appearance")
        clock.addTimeInterval(UpdateController.backgroundInterval - 1)
        updates.checkInBackground()
        precondition(backend.probes == 1, "Throttle repeated activation events")
        clock.addTimeInterval(1)
        updates.checkInBackground()
        precondition(backend.probes == 2, "Discover a release while the app stays open")
        // A click while a silent check is fetching the feed is queued and shown once.
        updates.checkForUpdates()
        precondition(backend.presentations == 0)
        backend.finish()
        precondition(backend.presentations == 1)
        backend.finish()
        precondition(backend.presentations == 1 && updates.availableVersion == "0.4.1",
                     "Do not reopen the dialog or erase the badge on dismissal/error")
        let restored = UpdateController(backend: TestBackend(), defaults: defaults, installedBuild: "4", automaticallyMonitor: false)
        precondition(restored.availableVersion == "0.4.1", "Restore known updates before the first network response")
        backend.notFound()
        precondition(updates.availableVersion == nil)
        let cleared = UpdateController(backend: TestBackend(), defaults: defaults, installedBuild: "4", automaticallyMonitor: false)
        precondition(cleared.availableVersion == nil, "A successful no-update result clears the cache")
        backend.found("0.4.1", build: "5")
        let installed = UpdateController(backend: TestBackend(), defaults: defaults, installedBuild: "5", automaticallyMonitor: false)
        precondition(installed.availableVersion == nil, "Hide the old badge after installing its build")
        let optedOut = TestBackend()
        optedOut.automaticallyChecks = false
        let manual = UpdateController(backend: optedOut, defaults: defaults, installedBuild: "5", automaticallyMonitor: false)
        manual.start()
        manual.checkInBackground()
        precondition(optedOut.probes == 0)
        manual.checkForUpdates()
        precondition(optedOut.presentations == 1, "Manual checks work when automatic checks are disabled")
        print("PASS: launch/background discovery, no unsolicited dialogs, persistent badge, throttling, queued clicks, no-update and installed-build invalidation, automatic-check preference")
    }
}

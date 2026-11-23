import AppKit
import Foundation

@main
struct BackgroundUpdateIntegration {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let host = Bundle(url: root.appendingPathComponent(".build/UpdateDiscoveryHost.app"))!
        let domain = host.bundleIdentifier!
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let backend = SparkleUpdateBackend(bundle: host)
        let updates = UpdateController(backend: backend, defaults: defaults, installedBuild: "4", automaticallyMonitor: false)
        updates.start()
        let deadline = Date().addingTimeInterval(20)
        while (updates.availableVersion == nil || !updates.canCheckForUpdates) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let counts = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Int]
        precondition(counts["appcast", default: 0] >= 1, "Sparkle should request the feed on app startup")
        precondition(counts["archive", default: 0] == 0, "Discovering updates must not start an unsolicited download")
        precondition(updates.availableVersion == "0.4.1", "Real Sparkle must publish the badge without Settings")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(updates.availableVersion == "0.4.1", "A completed probe must retain the update")
        precondition(NSApp.windows.allSatisfy { !$0.isVisible }, "Background discovery must not present an update dialog")
        print("PASS: real Sparkle startup discovery, retained badge, no archive download or window; no Settings view was created")
    }
}

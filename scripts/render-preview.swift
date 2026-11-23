import AppKit
import SwiftUI

@main
struct RenderPreview {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let directory = root.appendingPathComponent(".build/appearance-previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "dev.focuselle.preview." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let database = directory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let state = AppState(defaults: defaults, storageURL: database, resourceBundle: Bundle(path: root.appendingPathComponent(".build/Focuselle.app").path)!)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.language = "ru"
        state.showPlan = true
        state.addTask(title: "Одна важная задача")
        state.addTask(title: "Прочитать главу книги")
        state.chooseTask(state.dayTasks.first)
        for style in VisualStyle.allCases {
            for dark in [false, true] {
                state.visualStyle = style
                state.theme = dark ? .dark : .light
                try snapshot(state: state, dark: dark, name: style.rawValue + (dark ? "-dark" : "-light"), directory: directory)
            }
        }
        state.visualStyle = .focuselle
        state.theme = .light
        state.screen = .settings
        state.language = "ru"
        try snapshot(state: state, dark: false, name: "settings-ru", directory: directory)
        state.language = "ja"
        state.showPlan = false
        try snapshot(state: state, dark: false, name: "settings-ja", directory: directory)
        state.screen = .tasks
        state.language = "de"
        try snapshot(state: state, dark: false, name: "tasks-de", directory: directory)
        state.screen = .statistics
        state.language = "zh-Hans"
        try snapshot(state: state, dark: false, name: "statistics-zh", directory: directory)
        state.screen = .focus
        state.language = "ru"
        try snapshot(state: state, dark: false, name: "focuselle-compact", directory: directory, width: 400, height: 650)
        try snapshot(state: state, dark: false, name: "focuselle-minimal", directory: directory, width: 340, height: 400)
        state.language = "en"
        try snapshot(state: state, dark: true, name: "focuselle-controls-en", directory: directory, width: 650, height: 700, holdCommand: true)
        let manager = FileManager.default
        for name in ["focuselle-light", "focuselle-dark", "classic-light", "classic-dark", "settings-ru"] {
            let destination = root.appendingPathComponent("media/screenshots/" + name + ".png")
            try? manager.removeItem(at: destination)
            try manager.copyItem(at: directory.appendingPathComponent(name + ".png"), to: destination)
        }
        for name in ["media/screenshots/application.png", "landing/dist/assets/workspace.png"] {
            let destination = root.appendingPathComponent(name)
            try? manager.removeItem(at: destination)
            try manager.copyItem(at: directory.appendingPathComponent("focuselle-light.png"), to: destination)
        }
    }

    @MainActor static func snapshot(state: AppState, dark: Bool, name: String, directory: URL, width: CGFloat = 1060, height: CGFloat = 760, holdCommand: Bool = false) throws {
        let view = WorkspaceView(state: state, showMini: {})
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, state.locale)
            .frame(width: width, height: height)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        if holdCommand {
            let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .command,
                                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55)!
            NSApp.sendEvent(event)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            precondition(state.commandHeld, "Command shortcuts must be visible in the keyboard preview")
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        if holdCommand {
            let release = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                           context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55)!
            NSApp.sendEvent(release)
        }
        window.orderOut(nil)
        print("Rendered " + name)
    }
}

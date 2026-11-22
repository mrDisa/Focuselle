import SwiftUI
import AppKit

@main
struct FocuselleApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Focuselle", id: "main") {
            WorkspaceView(state: state, showMini: { delegate.showMini(state: state) })
                .preferredColorScheme(state.theme.scheme)
                .environment(\.locale, state.locale)
        }
        .defaultSize(width: 1000, height: 740)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .windowArrangement) {
                Button(state.text("miniTimer")) { delegate.showMini(state: state) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            CommandMenu(state.text("navigation")) {
                ForEach(Array(Screen.allCases.enumerated()), id: \.element.id) { index, screen in
                    Button(state.text(screen.titleKey)) { state.screen = screen }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Divider()
                Button(state.text("togglePlan")) { state.showPlan.toggle() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button(state.text(state.transportTitle)) { state.toggleTimer() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button(state.text("settings") + "…") {
                    state.screen = .settings
                    openWindow(id: "main")
                    delegate.showMain()
                }.keyboardShortcut(",")
            }
        }

        MenuBarExtra {
            MenuContent(state: state, showMain: delegate.showMain,
                        showMini: { delegate.showMini(state: state) })
        } label: {
            Label(state.timer.isRunning || state.hasProgress ? state.digits : "Focuselle", systemImage: "timer")
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var miniPanel: NSPanel?
    private var appearanceObservation: NSKeyValueObservation?
    private var dockIcons: [String: NSImage] = [:]
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateDockIcon() }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationDidBecomeActive(_ notification: Notification) { updateDockIcon() }

    private func updateDockIcon() {
        // Follow macOS itself, independently of the appearance chosen inside Focuselle.
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let name = dark ? "AppIcon" : "AppIconLight"
        if dockIcons[name] == nil,
           let url = Bundle.main.url(forResource: name, withExtension: dark ? "icns" : "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = false
            dockIcons[name] = image
        }
        if let image = dockIcons[name] { NSApp.applicationIconImage = image }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain()
        return true
    }
    func showMain() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })
            ?? NSApp.windows.first(where: { $0.title == "Focuselle" && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func showMini(state: AppState) {
        if miniPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 290, height: 235),
                                styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.title = "Focuselle · " + state.text("miniTimer")
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: MiniTimerView(state: state))
            panel.center()
            panel.setFrameAutosaveName("FocuselleMiniTimer")
            miniPanel = panel
        }
        miniPanel?.orderFrontRegardless()
    }
}

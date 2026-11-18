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
        .defaultSize(width: 1140, height: 760)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .windowArrangement) {
                Button(state.text("miniTimer")) { delegate.showMini(state: state) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            CommandMenu(state.text("navigation")) {
                ForEach(Array(Screen.allCases.enumerated()), id: \.element.id) { index, screen in
                    Button(state.text(screen.rawValue)) { state.screen = screen }
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 290, height: 215),
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

import AppKit
import SwiftUI

@main
struct RenderPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("FocusellePreview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let defaults = UserDefaults(suiteName: "dev.focuselle.artwork")!
        let state = AppState(defaults: defaults, storageURL: temporary.appendingPathComponent("preview.sqlite"),
                             resourceBundle: Bundle(path: root.appendingPathComponent(".build/Focuselle.app").path)!)
        state.language = "ru"
        state.theme = .dark
        state.showPlan = false
        state.addTask(title: "Одна важная задача")
        state.chooseTask(state.dayTasks.first)
        let view = VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(Color(hex: 0xED6A5F)).frame(width: 10, height: 10)
                Circle().fill(Color(hex: 0xF4BE50)).frame(width: 10, height: 10)
                Circle().fill(Color(hex: 0x61C454)).frame(width: 10, height: 10)
                Text("Focuselle").font(.system(size: 12, weight: .semibold)).padding(.leading, 14)
                Spacer()
                Image(systemName: "pip").foregroundStyle(.secondary)
                Image(systemName: "sidebar.right").foregroundStyle(.secondary).padding(.leading, 12)
            }.padding(.horizontal, 16).frame(height: 36).background(Color(hex: 0x1A1B1D))
            HStack(spacing: 0) {
                VStack(spacing: 16) {
                    ForEach(["sun.max.fill", "timer", "calendar", "chart.bar", "headphones"], id: \.self) { symbol in
                        Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Color(hex: 0x86A591))
                            .frame(width: 34, height: 32)
                            .background(symbol == "timer" ? Color(hex: 0x86A591).opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                    }
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                }.padding(.vertical, 24).frame(width: 52).background(Color(hex: 0x191B1C))
                Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                VStack(spacing: 15) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Время для главного").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text("Фокус").font(.system(size: 28, weight: .semibold, design: .rounded))
                        }
                        Spacer()
                        Text("✦ В своём ритме").font(.system(size: 11)).foregroundStyle(Color(hex: 0x86A591))
                    }.padding(.bottom, 4)
                    HStack(spacing: 8) {
                        ForEach(["25 / 5", "50 / 10", "90 / 10", "Свой режим"], id: \.self) { title in
                            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(title == "25 / 5" ? Color(hex: 0x86A591) : Color.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(title == "25 / 5" ? Color.white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }.padding(4).background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                    HStack(spacing: 20) {
                        Text("Фокус").foregroundStyle(Color(hex: 0x86A591))
                        Text("Короткий отдых")
                        Text("Длинный отдых")
                    }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 15).padding(.vertical, 9)
                        .background(Color.white.opacity(0.03), in: Capsule())
                    Text("◎ Одна важная задача ⌄").font(.system(size: 12)).foregroundStyle(Color(hex: 0x86A591))
                        .padding(.horizontal, 18).padding(.vertical, 8).background(Color.white.opacity(0.025), in: Capsule())
                    FocusDial(state: state).scaleEffect(0.78).frame(width: 255, height: 255)
                    TimerTransport(state: state)
                    Spacer(minLength: 4)
                    HStack {
                        Label("Только на твоём Mac", systemImage: "internaldrive")
                        Spacer()
                        Label("Звуки переходов", systemImage: "speaker.wave.2")
                    }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 12)
                        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                }.padding(24).frame(maxWidth: .infinity).background(Color(hex: 0x101112))
            }.frame(width: 940, height: 640)
        }
        .frame(width: 940, height: 676).environment(\.colorScheme, .dark).foregroundStyle(Color(hex: 0xF0F2F0)).environment(\.locale, Locale(identifier: "ru"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Preview", code: 1)
        }
        try png.write(to: root.appendingPathComponent("landing/dist/assets/workspace.png"))
        print("Rendered: landing/dist/assets/workspace.png")
    }
}

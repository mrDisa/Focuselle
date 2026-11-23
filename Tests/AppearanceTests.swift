import AppKit
import Foundation
import SwiftUI

@main
struct AppearanceTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let suite = "dev.focuselle.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temporary)
        }
        defaults.set("dark", forKey: "theme")
        defaults.set("ru", forKey: "language")
        let bundle = Bundle(path: root.appendingPathComponent(".build/Focuselle.app").path)!
        let state = AppState(defaults: defaults, storageURL: temporary.appendingPathComponent("test.sqlite"), resourceBundle: bundle)
        precondition(state.theme == .dark && state.language == "ru", "Keep existing mode and language")
        precondition(state.visualStyle == .focuselle, "Landing style is the new default")
        state.visualStyle = .classic
        precondition(defaults.string(forKey: "visualStyle") == "classic")
        state.visualStyle = .focuselle
        precondition(defaults.string(forKey: "visualStyle") == "focuselle")
        defaults.set("olive", forKey: "visualStyle")
        let migrated = AppState(defaults: defaults, storageURL: temporary.appendingPathComponent("migration.sqlite"), resourceBundle: bundle)
        precondition(migrated.visualStyle == .classic, "Retain selections from the earlier theme name")
        for dark in [false, true] {
            let reference = FocusPalette(phase: .focus, dark: dark, style: .classic)
            precondition(matches(reference.accent, dark ? 0x86A591 : 0x42634F))
            precondition(matches(reference.highlight, dark ? 0x2E4D3B : 0xD3E0D4))
            precondition(matches(reference.background, dark ? 0x101112 : 0xF5F6F3))
            precondition(matches(reference.ink, dark ? 0xF0F2F0 : 0x27352D))
            for phase in [FocusTimer.Phase.focus, .shortBreak, .longBreak] {
                let monochrome = FocusPalette(phase: phase, dark: dark, style: .focuselle)
                for color in [monochrome.accent, monochrome.highlight, monochrome.ink, monochrome.background, monochrome.panel, monochrome.border, monochrome.buttonInk] {
                    let rgb = NSColor(color).usingColorSpace(.sRGB)!
                    precondition(abs(rgb.redComponent - rgb.greenComponent) < 0.0001 && abs(rgb.greenComponent - rgb.blueComponent) < 0.0001, "Main theme must remain monochrome")
                }
            }
        }
        precondition(AppLanguage.preferred(["zh-CN"]) == "zh-Hans")
        precondition(AppLanguage.preferred(["pt-PT"]) == "pt-BR")
        precondition(AppLanguage.preferred(["ja-JP"]) == "ja")
        precondition(AppLanguage.preferred(["it-IT", "fr-FR"]) == "fr")
        precondition(AppLanguage.preferred(["unknown"]) == "en")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Focuselle/Resources/Localizable.xcstrings"))) as! [String: Any]
        let entries = catalog["strings"] as! [String: Any]
        let infoLanguages = Set(bundle.object(forInfoDictionaryKey: "CFBundleLocalizations") as! [String])
        precondition(infoLanguages == Set(AppLanguage.allCases.map(\.rawValue)))
        for language in AppLanguage.allCases {
            state.language = language.rawValue
            for key in entries.keys {
                let value = state.text(key)
                precondition(!value.isEmpty && value != key, "Missing \(language.rawValue) / \(key)")
            }
        }
        state.language = "missing"
        precondition(state.text("start") == "Start", "English fallback")
        print("Appearance/localization: saved preferences, locale matching and \(entries.count) strings × \(AppLanguage.allCases.count) languages passed")
    }
    @MainActor static func matches(_ color: Color, _ hex: UInt32) -> Bool {
        let actual = NSColor(color).usingColorSpace(.sRGB)!
        let expected = NSColor(Color(hex: hex)).usingColorSpace(.sRGB)!
        return abs(actual.redComponent - expected.redComponent) < 0.0001 && abs(actual.greenComponent - expected.greenComponent) < 0.0001 && abs(actual.blueComponent - expected.blueComponent) < 0.0001
    }
}

import AppKit
import Carbon.HIToolbox
import Foundation

struct ShortcutDefinition: Codable, Hashable, Sendable {
    static let storageKey = "globalShortcut"
    static let screenshotStorageKey = "screenshotShortcut"
    static let defaultsVersionKey = "shortcutDefaultsVersion"
    private static let currentDefaultsVersion = 2
    static let defaultShortcut = ShortcutDefinition(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: [.command]
    )
    static let defaultScreenshotShortcut = ShortcutDefinition(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: [.command, .option]
    )
    private static let legacyDefaultShortcut = ShortcutDefinition(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: [.control, .option]
    )

    let keyCode: UInt32
    private let modifierRawValue: UInt

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        modifierRawValue = modifiers
            .intersection([.command, .control, .option, .shift])
            .rawValue
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    var isValid: Bool {
        !modifiers.isEmpty && Self.keyNames[keyCode] != nil
    }

    var displayString: String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        value += Self.keyNames[keyCode] ?? "?"
        return value
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
        defaults.set(Self.currentDefaultsVersion, forKey: Self.defaultsVersionKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> ShortcutDefinition {
        guard
            let data = defaults.data(forKey: storageKey),
            let shortcut = try? JSONDecoder().decode(Self.self, from: data),
            shortcut.isValid
        else {
            defaultShortcut.save(to: defaults)
            return defaultShortcut
        }

        if defaults.integer(forKey: defaultsVersionKey) < currentDefaultsVersion {
            if shortcut == legacyDefaultShortcut {
                defaultShortcut.save(to: defaults)
                return defaultShortcut
            }
            defaults.set(currentDefaultsVersion, forKey: defaultsVersionKey)
        }
        return shortcut
    }

    func saveScreenshot(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.screenshotStorageKey)
    }

    static func loadScreenshot(
        from defaults: UserDefaults = .standard
    ) -> ShortcutDefinition {
        guard
            let data = defaults.data(forKey: screenshotStorageKey),
            let shortcut = try? JSONDecoder().decode(Self.self, from: data),
            shortcut.isValid
        else {
            defaultScreenshotShortcut.saveScreenshot(to: defaults)
            return defaultScreenshotShortcut
        }
        return shortcut
    }

    static func keyName(for keyCode: UInt32) -> String? {
        keyNames[keyCode]
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab", UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Home): "Home",
        UInt32(kVK_End): "End", UInt32(kVK_PageUp): "Page Up",
        UInt32(kVK_PageDown): "Page Down", UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→", UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]
}

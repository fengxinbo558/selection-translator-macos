import AppKit
import Testing
@testable import Huayi

@Suite("Shortcut definition")
struct ShortcutDefinitionTests {
    @Test func defaultShortcutIsCommandT() {
        let shortcut = ShortcutDefinition.defaultShortcut

        #expect(shortcut.keyCode == 17)
        #expect(shortcut.modifiers == [.command])
        #expect(shortcut.displayString == "⌘T")
    }

    @Test func defaultScreenshotShortcutIsOptionCommandT() {
        let shortcut = ShortcutDefinition.defaultScreenshotShortcut

        #expect(shortcut.keyCode == 17)
        #expect(shortcut.modifiers == [.command, .option])
        #expect(shortcut.displayString == "⌥⌘T")
    }

    @Test func screenshotShortcutRoundTripsThroughDefaults() throws {
        let suiteName = "ScreenshotShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected = ShortcutDefinition(keyCode: 3, modifiers: [.command, .shift])

        expected.saveScreenshot(to: defaults)

        #expect(ShortcutDefinition.loadScreenshot(from: defaults) == expected)
    }

    @Test func shortcutRequiresModifier() {
        #expect(!ShortcutDefinition(keyCode: 17, modifiers: []).isValid)
        #expect(ShortcutDefinition(keyCode: 17, modifiers: [.command]).isValid)
    }

    @Test func displayUsesStableModifierOrder() {
        let shortcut = ShortcutDefinition(
            keyCode: 8,
            modifiers: [.command, .shift, .option, .control]
        )

        #expect(shortcut.displayString == "⌃⌥⇧⌘C")
    }

    @Test func shortcutRoundTripsThroughDefaults() throws {
        let suiteName = "ShortcutDefinitionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected = ShortcutDefinition(keyCode: 3, modifiers: [.command, .option])

        expected.save(to: defaults)

        #expect(ShortcutDefinition.load(from: defaults) == expected)
    }

    @Test func legacyDefaultMigratesToCommandT() throws {
        let suiteName = "ShortcutDefinitionMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = ShortcutDefinition(keyCode: 17, modifiers: [.control, .option])
        legacy.save(to: defaults)
        defaults.removeObject(forKey: ShortcutDefinition.defaultsVersionKey)

        let loaded = ShortcutDefinition.load(from: defaults)

        #expect(loaded == .defaultShortcut)
        #expect(loaded.displayString == "⌘T")
        #expect(defaults.integer(forKey: ShortcutDefinition.defaultsVersionKey) == 2)
    }
}

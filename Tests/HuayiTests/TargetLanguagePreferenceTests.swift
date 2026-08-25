import Foundation
import Testing
@testable import Huayi

@Suite("Target language preference")
struct TargetLanguagePreferenceTests {
    @Test func defaultsToEnglish() {
        let defaults = ephemeralDefaults()

        #expect(TargetLanguagePreference.load(from: defaults) == "en")
    }

    @Test func persistsSelectedLanguage() {
        let defaults = ephemeralDefaults()

        TargetLanguagePreference.save("ja", to: defaults)

        #expect(TargetLanguagePreference.load(from: defaults) == "ja")
    }

    @Test func migratesOldUnsupportedPreferenceToEnglish() {
        let defaults = ephemeralDefaults()
        defaults.set("fr", forKey: TargetLanguagePreference.storageKey)

        #expect(TargetLanguagePreference.load(from: defaults) == "en")
        #expect(defaults.string(forKey: TargetLanguagePreference.storageKey) == "en")
    }

    @Test func normalizesRegionalEnglishPreference() {
        let defaults = ephemeralDefaults()
        defaults.set("en-GB", forKey: TargetLanguagePreference.storageKey)

        #expect(TargetLanguagePreference.load(from: defaults) == "en")
    }

    private func ephemeralDefaults() -> UserDefaults {
        let name = "TargetLanguagePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

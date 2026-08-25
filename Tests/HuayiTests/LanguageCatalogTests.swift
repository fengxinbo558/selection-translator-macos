import Foundation
import Testing
@testable import Huayi

@MainActor
@Suite("Language catalog")
struct LanguageCatalogTests {
    private let options = [
        LanguageOption(identifier: "zh-Hans", localizedName: "简体中文", englishName: "Chinese, Simplified"),
        LanguageOption(identifier: "en", localizedName: "英语", englishName: "English"),
        LanguageOption(identifier: "ja", localizedName: "日语", englishName: "Japanese"),
    ]

    @Test func searchesLocalizedEnglishAndIdentifier() {
        let catalog = LanguageCatalog(options: options, defaults: ephemeralDefaults())

        #expect(catalog.filteredOptions(query: "简体").map(\.identifier) == ["zh-Hans"])
        #expect(catalog.filteredOptions(query: "english").map(\.identifier) == ["en"])
        #expect(catalog.filteredOptions(query: "JA").map(\.identifier) == ["ja"])
    }

    @Test func emptyQueryReturnsAllOptions() {
        let catalog = LanguageCatalog(options: options, defaults: ephemeralDefaults())

        #expect(catalog.filteredOptions(query: "  ") == options)
    }

    @Test func recentLanguagesAreUniqueAndLimitedToFive() {
        let allOptions = (0..<7).map {
            LanguageOption(identifier: "x-\($0)", localizedName: "语言\($0)", englishName: "Language \($0)")
        }
        let catalog = LanguageCatalog(options: allOptions, defaults: ephemeralDefaults())

        for option in allOptions { catalog.recordUse(option) }
        catalog.recordUse(allOptions[4])

        #expect(catalog.recentOptions.map(\.identifier) == ["x-4", "x-6", "x-5", "x-3", "x-2"])
    }

    private func ephemeralDefaults() -> UserDefaults {
        let name = "LanguageCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

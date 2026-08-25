import Foundation

struct LanguageOption: Identifiable, Hashable, Sendable {
    let identifier: String
    let localizedName: String
    let englishName: String

    var id: String { identifier }
    var language: Locale.Language { Locale.Language(identifier: identifier) }

    init(identifier: String, localizedName: String, englishName: String) {
        self.identifier = identifier
        self.localizedName = localizedName
        self.englishName = englishName
    }

    init(language: Locale.Language, displayLocale: Locale = .current) {
        let identifier = language.minimalIdentifier
        self.identifier = identifier
        localizedName = displayLocale.localizedString(forIdentifier: identifier)
            ?? displayLocale.localizedString(forLanguageCode: identifier)
            ?? identifier
        englishName = Locale(identifier: "en").localizedString(forIdentifier: identifier)
            ?? Locale(identifier: "en").localizedString(forLanguageCode: identifier)
            ?? identifier
    }
}

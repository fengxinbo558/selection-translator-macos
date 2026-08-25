import Foundation

struct TargetLanguagePreference {
    static let storageKey = "preferredTargetLanguage"
    static let defaultIdentifier = "en"

    static func load(from defaults: UserDefaults = .standard) -> String {
        guard let identifier = defaults.string(forKey: storageKey),
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return defaultIdentifier
        }
        let normalized = identifier
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased() ?? ""
        guard LanguageCatalog.partnerLanguageIdentifiers.contains(normalized) else {
            defaults.set(defaultIdentifier, forKey: storageKey)
            return defaultIdentifier
        }
        return normalized
    }

    static func save(_ identifier: String, to defaults: UserDefaults = .standard) {
        let normalized = identifier
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased() ?? defaultIdentifier
        defaults.set(
            LanguageCatalog.partnerLanguageIdentifiers.contains(normalized)
                ? normalized : defaultIdentifier,
            forKey: storageKey
        )
    }
}

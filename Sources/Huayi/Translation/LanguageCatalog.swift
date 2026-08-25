import Combine
import Foundation
@preconcurrency import Translation

@MainActor
final class LanguageCatalog: ObservableObject {
    nonisolated static let partnerLanguageIdentifiers = ["en", "ja", "ko"]

    @Published private(set) var options: [LanguageOption]
    @Published private(set) var isLoading = false

    private let defaults: UserDefaults
    private let recentKey = "recentTargetLanguages"
    private var loadTask: Task<[Locale.Language], Never>?

    init(options: [LanguageOption] = [], defaults: UserDefaults = .standard) {
        self.options = options
        self.defaults = defaults
    }

    var recentOptions: [LanguageOption] {
        let byIdentifier = Dictionary(uniqueKeysWithValues: options.map { ($0.identifier, $0) })
        return recentIdentifiers.compactMap { byIdentifier[$0] }
    }

    func loadSupportedLanguages() async {
        guard options.isEmpty else { return }

        if let loadTask {
            let languages = await loadTask.value
            apply(languages)
            return
        }

        isLoading = true
        let task = Task { await LanguageAvailability().supportedLanguages }
        loadTask = task
        let languages = await task.value
        loadTask = nil
        apply(languages)
    }

    private func apply(_ languages: [Locale.Language]) {
        guard options.isEmpty else {
            isLoading = false
            return
        }
        let supportedCodes = Set(languages.map { languageCode($0) })
        options = Self.partnerLanguageIdentifiers
            .filter { supportedCodes.contains($0) }
            .map { LanguageOption(language: Locale.Language(identifier: $0)) }
        isLoading = false
    }

    private func languageCode(_ language: Locale.Language) -> String {
        language.minimalIdentifier
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased() ?? language.minimalIdentifier.lowercased()
    }

    func filteredOptions(query: String) -> [LanguageOption] {
        let term = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !term.isEmpty else { return options }
        return options.filter { option in
            normalize(option.localizedName).contains(term)
                || normalize(option.englishName).contains(term)
                || normalize(option.identifier).contains(term)
        }
    }

    func recordUse(_ option: LanguageOption) {
        var identifiers = recentIdentifiers.filter { $0 != option.identifier }
        identifiers.insert(option.identifier, at: 0)
        defaults.set(Array(identifiers.prefix(5)), forKey: recentKey)
        objectWillChange.send()
    }

    private var recentIdentifiers: [String] {
        defaults.stringArray(forKey: recentKey) ?? []
    }

    private func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}

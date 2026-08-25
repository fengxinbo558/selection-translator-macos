import Foundation
import Testing
import Translation
@testable import Huayi

@MainActor
@Suite("Compact translation model")
struct CompactTranslationModelTests {
    @Test func installedPairAutomaticallyReplacesSelection() async {
        var replacement: String?
        let model = makeModel(replacement: { replacement = $0 })
        let english = option("en", "英语")

        model.start(to: english)
        await translate(model, target: english, result: "Hello")

        #expect(replacement == "Hello")
        #expect(model.state == .replaced)
        #expect(model.translatedText == "Hello")
    }

    @Test func readOnlySelectionKeepsResultInSamePanel() async {
        var replacementCount = 0
        let model = makeModel(
            capability: .copyOnly,
            replacement: { _ in replacementCount += 1 }
        )
        let english = option("en", "英语")

        model.start(to: english)
        await translate(model, target: english, result: "Hello")

        #expect(replacementCount == 0)
        #expect(model.state == .resultReady)
        #expect(model.translatedText == "Hello")
    }

    @Test func choosingAnotherLanguageIsRememberedAndStartsNewRequest() {
        let english = option("en", "英语")
        let japanese = option("ja", "日语")
        let catalog = LanguageCatalog(options: [english, japanese], defaults: defaults())
        let model = makeModel(catalog: catalog)
        var rememberedIdentifier: String?
        model.onTargetChanged = { rememberedIdentifier = $0 }

        model.start(to: english)
        let englishRequest = model.currentRequestID
        model.selectTarget(identifier: "ja")

        #expect(model.currentRequestID > englishRequest)
        #expect(model.selectedTarget == japanese)
        #expect(rememberedIdentifier == "ja")
        #expect(model.configuration?.target?.minimalIdentifier == "ja")
    }

    @Test func englishSourceWithEnglishPartnerTargetsChinese() {
        let english = option("en", "英语")
        let model = CompactTranslationModel(
            snapshot: SelectionSnapshot(
                processIdentifier: 1,
                bundleIdentifier: "test.app",
                focusedElement: nil,
                originalText: "Hello",
                selectedRange: nil,
                replacementCapability: .copyOnly,
                capturedAt: Date()
            ),
            catalog: LanguageCatalog(options: [english], defaults: defaults()),
            replaceAction: { _ in },
            copyAction: { _ in },
            languageDetector: { _ in Locale.Language(identifier: "en") },
            availabilityChecker: { _, _ in .installed }
        )

        model.start(to: english)

        #expect(model.configuration?.target?.minimalIdentifier == "zh")
        #expect(model.directionText == "英语 → 中文")
    }

    @Test func knownAbbreviationUsesEnglishFullNameForTranslation() async {
        let english = option("en", "英语")
        let model = CompactTranslationModel(
            snapshot: SelectionSnapshot(
                processIdentifier: 1,
                bundleIdentifier: "test.app",
                focusedElement: nil,
                originalText: "LLM",
                selectedRange: nil,
                replacementCapability: .copyOnly,
                capturedAt: Date()
            ),
            catalog: LanguageCatalog(options: [english], defaults: defaults()),
            replaceAction: { _ in },
            copyAction: { _ in },
            languageDetector: { _ in Locale.Language(identifier: "en") },
            availabilityChecker: { _, _ in .installed }
        )

        model.start(to: english)
        var translatedInput: String?
        await model.performTranslation(
            requestID: model.currentRequestID,
            sourceLanguage: Locale.Language(identifier: "en"),
            targetLanguage: Locale.Language(identifier: "zh-Hans"),
            prepare: {},
            translate: {
                translatedInput = $0
                return "大语言模型"
            }
        )

        #expect(model.abbreviationExplanation?.fullName == "Large Language Model")
        #expect(model.speechLanguageIdentifier == "zh-Hans")
        #expect(translatedInput == "Large Language Model")
        #expect(model.translatedText == "大语言模型")
    }

    @Test func unknownEnglishAbbreviationOverridesJapaneseMisidentification() {
        let english = option("en", "英语")
        let model = CompactTranslationModel(
            snapshot: SelectionSnapshot(
                processIdentifier: 1,
                bundleIdentifier: "test.app",
                focusedElement: nil,
                originalText: "XYZQ",
                selectedRange: nil,
                replacementCapability: .copyOnly,
                capturedAt: Date()
            ),
            catalog: LanguageCatalog(options: [english], defaults: defaults()),
            replaceAction: { _ in },
            copyAction: { _ in },
            languageDetector: { _ in Locale.Language(identifier: "ja") },
            availabilityChecker: { _, _ in .installed }
        )

        model.start(to: english)

        #expect(model.abbreviationExplanation == nil)
        #expect(model.configuration?.source?.minimalIdentifier == "en")
        #expect(model.configuration?.target?.minimalIdentifier == "zh")
        #expect(model.directionText == "英语 → 中文")
    }

    @Test func staleTranslationCannotReplaceNewerLanguage() async {
        var replacements: [String] = []
        let english = option("en", "英语")
        let japanese = option("ja", "日语")
        let catalog = LanguageCatalog(options: [english, japanese], defaults: defaults())
        let model = makeModel(catalog: catalog, replacement: { replacements.append($0) })

        model.start(to: english)
        let staleRequest = model.currentRequestID
        model.selectTarget(identifier: "ja")

        await model.performTranslation(
            requestID: staleRequest,
            sourceLanguage: Locale.Language(identifier: "zh-Hans"),
            targetLanguage: english.language,
            prepare: {},
            translate: { _ in "Hello" }
        )

        #expect(replacements.isEmpty)
        #expect(model.selectedTarget == japanese)
    }

    @Test func translationAlwaysUsesOriginalTextAfterLanguageSwitch() async {
        let english = option("en", "英语")
        let japanese = option("ja", "日语")
        let catalog = LanguageCatalog(options: [english, japanese], defaults: defaults())
        let model = makeModel(catalog: catalog)
        var translatedSource: String?

        model.start(to: english)
        await translate(model, target: english, result: "Hello")
        model.selectTarget(identifier: "ja")
        await model.performTranslation(
            requestID: model.currentRequestID,
            sourceLanguage: Locale.Language(identifier: "zh-Hans"),
            targetLanguage: japanese.language,
            prepare: {},
            translate: {
                translatedSource = $0
                return "こんにちは"
            }
        )

        #expect(translatedSource == "你好")
    }

    @Test func stalledTranslationStopsWithTimeoutError() async {
        let model = makeModel(localTranslationTimeout: .milliseconds(30))
        let english = option("en", "英语")
        model.start(to: english)
        let requestID = model.currentRequestID

        let work = Task {
            await model.performTranslation(
                requestID: requestID,
                sourceLanguage: Locale.Language(identifier: "zh-Hans"),
                targetLanguage: english.language,
                prepare: {},
                translate: { _ in
                    try await Task.sleep(for: .seconds(5))
                    return "Too late"
                }
            )
        }
        try? await Task.sleep(for: .milliseconds(300))

        #expect(model.state == .error(.translationTimedOut))
        #expect(!model.state.isBusy)
        #expect(model.configuration == nil)
        work.cancel()
    }

    private func translate(
        _ model: CompactTranslationModel,
        target: LanguageOption,
        result: String
    ) async {
        await model.performTranslation(
            requestID: model.currentRequestID,
            sourceLanguage: Locale.Language(identifier: "zh-Hans"),
            targetLanguage: target.language,
            prepare: {},
            translate: { _ in result }
        )
    }

    private func makeModel(
        catalog: LanguageCatalog? = nil,
        capability: ReplacementCapability = .direct,
        localTranslationTimeout: Duration = .seconds(20),
        replacement: @escaping CompactTranslationModel.ReplaceAction = { _ in }
    ) -> CompactTranslationModel {
        CompactTranslationModel(
            snapshot: snapshot(capability: capability),
            catalog: catalog ?? LanguageCatalog(options: [], defaults: defaults()),
            replaceAction: replacement,
            copyAction: { _ in },
            localTranslationTimeout: localTranslationTimeout,
            languageDetector: { _ in Locale.Language(identifier: "zh-Hans") },
            availabilityChecker: { _, _ in .installed }
        )
    }

    private func snapshot(capability: ReplacementCapability) -> SelectionSnapshot {
        SelectionSnapshot(
            processIdentifier: 1,
            bundleIdentifier: "test.app",
            focusedElement: nil,
            originalText: "你好",
            selectedRange: CFRange(location: 4, length: 2),
            replacementCapability: capability,
            capturedAt: Date()
        )
    }

    private func option(_ identifier: String, _ name: String) -> LanguageOption {
        LanguageOption(identifier: identifier, localizedName: name, englishName: name)
    }

    private func defaults() -> UserDefaults {
        let name = "CompactTranslationModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

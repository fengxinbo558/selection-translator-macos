import Foundation
import Testing
import Translation
@testable import Huayi

@MainActor
@Suite("Translation panel model")
struct TranslationPanelModelTests {
    @Test func selectingLanguageStartsPreparation() {
        let model = makeModel(sourceLanguage: "zh-Hans")
        let english = LanguageOption(identifier: "en", localizedName: "英语", englishName: "English")

        model.beginTranslation(to: english)

        #expect(model.state == .translating)
        #expect(model.selectedTarget == english)
        #expect(model.configuration?.target?.minimalIdentifier == "en")
        #expect(model.speechLanguageIdentifier == "en")
        #expect(
            SpeechLanguageResolver.voiceLanguage(for: model.sourceSpeechLanguageIdentifier)
                == "zh-CN"
        )
    }

    @Test func installedPairSkipsPreparation() async {
        var preparationCount = 0
        var translationCount = 0
        let model = makeModel(
            sourceLanguage: "zh-Hans",
            availability: { _, _ in .installed }
        )
        let english = LanguageOption(identifier: "en", localizedName: "英语", englishName: "English")
        model.beginTranslation(to: english)

        await model.performTranslation(
            requestID: model.currentRequestID,
            sourceLanguage: Locale.Language(identifier: "zh-Hans"),
            targetLanguage: english.language,
            prepare: { preparationCount += 1 },
            translate: { _ in
                translationCount += 1
                return "Hello"
            }
        )

        #expect(preparationCount == 0)
        #expect(translationCount == 1)
        #expect(model.state == .resultReady)
        #expect(model.translatedText == "Hello")
    }

    @Test func supportedPairPreparesOnceBeforeTranslation() async {
        var preparationCount = 0
        let model = makeModel(
            sourceLanguage: "zh-Hant",
            availability: { _, _ in .supported }
        )
        let english = LanguageOption(identifier: "en", localizedName: "英语", englishName: "English")
        model.beginTranslation(to: english)

        await model.performTranslation(
            requestID: model.currentRequestID,
            sourceLanguage: Locale.Language(identifier: "zh-Hant"),
            targetLanguage: english.language,
            prepare: { preparationCount += 1 },
            translate: { _ in "Hello" }
        )

        #expect(preparationCount == 1)
        #expect(model.state == .resultReady)
    }

    @Test func cancellationReturnsToPickerWithoutError() async {
        let model = makeModel(
            sourceLanguage: "zh-Hans",
            availability: { _, _ in .installed }
        )
        let english = LanguageOption(identifier: "en", localizedName: "英语", englishName: "English")
        model.beginTranslation(to: english)

        await model.performTranslation(
            requestID: model.currentRequestID,
            sourceLanguage: Locale.Language(identifier: "zh-Hans"),
            targetLanguage: english.language,
            prepare: {},
            translate: { _ in throw CancellationError() }
        )

        #expect(model.state == .idle)
        #expect(model.configuration == nil)
    }

    @Test func staleRequestCannotOverwriteLatestState() async {
        var staleTranslationRan = false
        let model = makeModel(
            sourceLanguage: "zh-Hans",
            availability: { _, _ in .installed }
        )
        let english = LanguageOption(identifier: "en", localizedName: "英语", englishName: "English")
        let japanese = LanguageOption(identifier: "ja", localizedName: "日语", englishName: "Japanese")
        model.beginTranslation(to: english)
        let staleRequestID = model.currentRequestID
        model.returnToLanguageList()
        model.beginTranslation(to: japanese)

        await model.performTranslation(
            requestID: staleRequestID,
            sourceLanguage: Locale.Language(identifier: "zh-Hans"),
            targetLanguage: english.language,
            prepare: {},
            translate: { _ in
                staleTranslationRan = true
                return "Old result"
            }
        )

        #expect(!staleTranslationRan)
        #expect(model.selectedTarget == japanese)
        #expect(model.translatedText == nil)
        #expect(model.state == .translating)
    }

    @Test func successfulTranslationShowsResultWithoutReplacing() async {
        var replacement: String?
        let defaults = ephemeralDefaults()
        let english = LanguageOption(identifier: "en", localizedName: "英语", englishName: "English")
        let catalog = LanguageCatalog(options: [english], defaults: defaults)
        let model = makeModel(
            catalog: catalog,
            sourceLanguage: "zh-Hans",
            replacement: { text, _ in
            replacement = text
            }
        )
        model.beginTranslation(to: english)

        await model.completeTranslation("Hello")

        #expect(replacement == nil)
        #expect(model.state == .resultReady)
        #expect(model.translatedText == "Hello")
        #expect(catalog.recentOptions == [english])
    }

    @Test func replacementOnlyRunsAfterExplicitAction() async {
        var replacement: String?
        let model = makeModel(
            sourceLanguage: "zh-Hans",
            replacement: { text, _ in replacement = text }
        )
        let english = LanguageOption(identifier: "en", localizedName: "英语", englishName: "English")
        model.beginTranslation(to: english)
        await model.completeTranslation("Hello")

        await model.replaceTranslation()

        #expect(replacement == "Hello")
        #expect(model.state == .success)
    }

    @Test func manualModeRequiresTextAndCannotReplace() {
        let model = makeModel(sourceLanguage: "zh-Hans", isManualEntry: true)
        model.sourceText = ""
        let english = LanguageOption(identifier: "en", localizedName: "英语", englishName: "English")

        model.beginTranslation(to: english)

        #expect(model.state == .error(.noSelection))
        #expect(model.configuration == nil)
        #expect(!model.canReplace)
    }

    @Test func selectedPartnerLanguageTranslatesBackToChinese() {
        let model = makeModel(sourceLanguage: "en")
        let english = LanguageOption(identifier: "en", localizedName: "英语", englishName: "English")

        model.beginTranslation(to: english)

        #expect(model.state == .translating)
        #expect(model.configuration?.target?.minimalIdentifier == "zh")
        #expect(model.directionText == "英语 → 中文")
    }

    @Test func knownAbbreviationUsesEnglishFullNameForTranslation() async {
        let model = makeModel(sourceLanguage: "ro")
        model.sourceText = "API"
        let english = LanguageOption(identifier: "en", localizedName: "英语", englishName: "English")
        model.beginTranslation(to: english)
        var translatedInput: String?

        await model.performTranslation(
            requestID: model.currentRequestID,
            sourceLanguage: Locale.Language(identifier: "en"),
            targetLanguage: Locale.Language(identifier: "zh-Hans"),
            prepare: {},
            translate: {
                translatedInput = $0
                return "应用程序编程接口"
            }
        )

        #expect(model.abbreviationExplanation?.fullName == "Application Programming Interface")
        #expect(model.sourceSpeechLanguageIdentifier == "en")
        #expect(model.configuration?.source?.minimalIdentifier == "en")
        #expect(model.configuration?.target?.minimalIdentifier == "zh")
        #expect(translatedInput == "Application Programming Interface")
        #expect(model.translatedText == "应用程序编程接口")
    }

    @Test func unknownEnglishAbbreviationOverridesDutchMisidentification() {
        let model = makeModel(sourceLanguage: "nl")
        model.sourceText = "XYZQ"
        let english = LanguageOption(identifier: "en", localizedName: "英语", englishName: "English")

        model.beginTranslation(to: english)

        #expect(model.abbreviationExplanation == nil)
        #expect(model.sourceSpeechLanguageIdentifier == "en")
        #expect(model.configuration?.source?.minimalIdentifier == "en")
        #expect(model.configuration?.target?.minimalIdentifier == "zh")
        #expect(model.directionText == "英语 → 中文")
    }

    @Test func duplicateSubmissionIsIgnoredWhileBusy() {
        let model = makeModel(sourceLanguage: "zh-Hans")
        let english = LanguageOption(identifier: "en", localizedName: "英语", englishName: "English")
        let japanese = LanguageOption(identifier: "ja", localizedName: "日语", englishName: "Japanese")

        model.beginTranslation(to: english)
        model.beginTranslation(to: japanese)

        #expect(model.selectedTarget == english)
    }

    @Test func consecutiveInputRearmsWithFreshConfiguration() async {
        let model = makeModel(sourceLanguage: "zh-Hans", isManualEntry: true)
        let english = LanguageOption(
            identifier: "en",
            localizedName: "英语",
            englishName: "English"
        )
        model.beginTranslation(to: english)
        let firstRequestID = model.currentRequestID
        await model.completeTranslation("First")

        model.sourceText = "这是第二段中文。"
        model.restartForCurrentTarget()

        #expect(model.currentRequestID > firstRequestID)
        #expect(model.configuration == nil)
        await waitForConfiguration(on: model)
        #expect(model.configuration?.target?.minimalIdentifier == "en")
        #expect(model.state == .translating)
        #expect(model.translatedText == nil)
    }

    @Test func manualEntryCanTranslateRepeatedlyAcrossThreeCycles() async {
        let model = makeModel(sourceLanguage: "zh-Hans", isManualEntry: true)
        let english = LanguageOption(
            identifier: "en",
            localizedName: "英语",
            englishName: "English"
        )
        model.beginTranslation(to: english)

        for cycle in 1...3 {
            if cycle > 1 {
                model.sourceText = "这是第\(cycle)轮。"
                model.restartForCurrentTarget()
                #expect(model.configuration == nil)
                await waitForConfiguration(on: model)
            }

            let requestID = model.currentRequestID
            await model.performTranslation(
                requestID: requestID,
                sourceLanguage: Locale.Language(identifier: "zh-Hans"),
                targetLanguage: english.language,
                prepare: {},
                translate: { _ in "Round \(cycle)" }
            )

            #expect(model.state == .resultReady)
            #expect(model.translatedText == "Round \(cycle)")
        }
    }

    @Test func rapidRewriteOnlyStartsLatestDeferredConfiguration() async {
        let model = makeModel(sourceLanguage: "zh-Hans", isManualEntry: true)
        let english = LanguageOption(
            identifier: "en",
            localizedName: "英语",
            englishName: "English"
        )
        model.beginTranslation(to: english)
        await model.completeTranslation("First")

        model.sourceText = "将被替换的第二轮"
        model.restartForCurrentTarget()
        let staleRequestID = model.currentRequestID
        model.sourceText = "最终保留的第三轮"
        model.restartForCurrentTarget()
        let latestRequestID = model.currentRequestID
        await waitForConfiguration(on: model)

        var staleTranslationRan = false
        await model.performTranslation(
            requestID: staleRequestID,
            sourceLanguage: Locale.Language(identifier: "zh-Hans"),
            targetLanguage: english.language,
            prepare: {},
            translate: { _ in
                staleTranslationRan = true
                return "Stale"
            }
        )
        await model.performTranslation(
            requestID: latestRequestID,
            sourceLanguage: Locale.Language(identifier: "zh-Hans"),
            targetLanguage: english.language,
            prepare: {},
            translate: { source in
                #expect(source == "最终保留的第三轮")
                return "Latest"
            }
        )

        #expect(!staleTranslationRan)
        #expect(model.translatedText == "Latest")
        #expect(model.state == .resultReady)
    }

    @Test func stalledTranslationStopsWithTimeoutError() async {
        let model = makeModel(
            sourceLanguage: "zh-Hans",
            localTranslationTimeout: .milliseconds(30)
        )
        let english = LanguageOption(
            identifier: "en",
            localizedName: "英语",
            englishName: "English"
        )
        model.beginTranslation(to: english)
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

    @Test func translationSessionThatNeverStartsStopsWithTimeoutError() async {
        let model = makeModel(
            sourceLanguage: "zh-Hans",
            localTranslationTimeout: .milliseconds(30)
        )
        let english = LanguageOption(
            identifier: "en",
            localizedName: "英语",
            englishName: "English"
        )

        model.beginTranslation(to: english)
        try? await Task.sleep(for: .milliseconds(300))

        #expect(model.state == .error(.translationTimedOut))
        #expect(model.configuration == nil)
        #expect(!model.state.isBusy)
    }

    private func makeModel(
        catalog: LanguageCatalog? = nil,
        sourceLanguage: String,
        isManualEntry: Bool = false,
        localTranslationTimeout: Duration = .seconds(20),
        availability: @escaping TranslationPanelModel.AvailabilityChecker = { _, _ in .installed },
        replacement: @escaping TranslationPanelModel.ReplaceAction = { _, _ in }
    ) -> TranslationPanelModel {
        TranslationPanelModel(
            snapshot: SelectionSnapshot(
                processIdentifier: 1,
                bundleIdentifier: "test.app",
                focusedElement: nil,
                originalText: "这是一段用于测试的中文文字。",
                selectedRange: nil,
                replacementCapability: .direct,
                capturedAt: Date()
            ),
            catalog: catalog ?? LanguageCatalog(options: [], defaults: ephemeralDefaults()),
            replaceAction: replacement,
            copyAction: { _ in },
            isManualEntry: isManualEntry,
            localTranslationTimeout: localTranslationTimeout,
            languageDetector: { _ in Locale.Language(identifier: sourceLanguage) },
            availabilityChecker: availability
        )
    }

    private func waitForConfiguration(on model: TranslationPanelModel) async {
        for _ in 0..<20 {
            if model.configuration != nil { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func ephemeralDefaults() -> UserDefaults {
        let name = "TranslationPanelModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

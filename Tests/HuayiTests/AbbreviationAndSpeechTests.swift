import AVFoundation
import Testing
@testable import Huayi

@Suite("Abbreviation glossary")
struct AbbreviationGlossaryTests {
    @Test func returnsFullNameMeaningAndUsage() {
        let explanation = AbbreviationGlossary.explanation(for: "RAG")

        #expect(explanation?.fullName == "Retrieval-Augmented Generation")
        #expect(explanation?.chineseMeaning == "检索增强生成")
        #expect(explanation?.usage.contains("检索") == true)
    }

    @Test func acceptsCaseAndSeparatorVariants() {
        #expect(AbbreviationGlossary.explanation(for: "rag")?.abbreviation == "RAG")
        #expect(AbbreviationGlossary.explanation(for: "R.A.G.")?.abbreviation == "RAG")
        #expect(AbbreviationGlossary.explanation(for: "CI/CD")?.abbreviation == "CI/CD")
        #expect(AbbreviationGlossary.explanation(for: "utf-8")?.abbreviation == "UTF-8")
        #expect(AbbreviationGlossary.explanation(for: "k8s")?.fullName == "Kubernetes")
    }

    @Test func ordinaryTextAndUnknownAcronymsAreNotMisidentified() {
        #expect(AbbreviationGlossary.explanation(for: "hello") == nil)
        #expect(AbbreviationGlossary.explanation(for: "这是一个普通句子") == nil)
        #expect(AbbreviationGlossary.explanation(for: "XYZQ") == nil)
    }
}

@Suite("Speech language resolver")
struct SpeechLanguageResolverTests {
    @Test func mapsSupportedTranslationLanguagesToSystemVoices() {
        #expect(SpeechLanguageResolver.voiceLanguage(for: "en") == "en-US")
        #expect(SpeechLanguageResolver.voiceLanguage(for: "ja") == "ja-JP")
        #expect(SpeechLanguageResolver.voiceLanguage(for: "ko") == "ko-KR")
        #expect(SpeechLanguageResolver.voiceLanguage(for: "zh-Hans") == "zh-CN")
        #expect(SpeechLanguageResolver.voiceLanguage(for: "zh-Hant") == "zh-TW")
    }

    @Test func keepsUnknownLocaleAndDefaultsEmptyToEnglish() {
        #expect(SpeechLanguageResolver.voiceLanguage(for: "fr-FR") == "fr-FR")
        #expect(SpeechLanguageResolver.voiceLanguage(for: nil) == "en-US")
        #expect(SpeechLanguageResolver.voiceLanguage(for: "") == "en-US")
    }

    @Test func avoidsNoveltyAndEloquenceVoices() {
        for identifier in ["en", "zh-Hans", "ja", "ko"] {
            let selected = SpeechVoiceResolver.voice(for: identifier)?.identifier.lowercased()
            #expect(selected?.contains(".eloquence.") != true)
            #expect(selected?.contains(".speech.synthesis.") != true)
        }
    }

    @Test func premiumAndEnhancedQualityOutrankCompactPreferences() {
        let compactPreferred = SpeechVoiceResolver.rankingScore(
            qualityRawValue: AVSpeechSynthesisVoiceQuality.default.rawValue,
            name: "Samantha",
            identifier: "com.apple.voice.compact.en-US.Samantha",
            language: "en-US"
        )
        let enhanced = SpeechVoiceResolver.rankingScore(
            qualityRawValue: AVSpeechSynthesisVoiceQuality.enhanced.rawValue,
            name: "Ava",
            identifier: "com.apple.voice.enhanced.en-US.Ava",
            language: "en-US"
        )
        let premium = SpeechVoiceResolver.rankingScore(
            qualityRawValue: AVSpeechSynthesisVoiceQuality.premium.rawValue,
            name: "Zoe",
            identifier: "com.apple.voice.premium.en-US.Zoe",
            language: "en-US"
        )

        #expect(enhanced > compactPreferred)
        #expect(premium > enhanced)
    }

    @Test func siriCompactOutranksOlderCompactFallbacks() {
        let siri = SpeechVoiceResolver.rankingScore(
            qualityRawValue: AVSpeechSynthesisVoiceQuality.default.rawValue,
            name: "Nicky",
            identifier: "com.apple.ttsbundle.siri_nicky_en-US_compact",
            language: "en-US"
        )
        let samantha = SpeechVoiceResolver.rankingScore(
            qualityRawValue: AVSpeechSynthesisVoiceQuality.default.rawValue,
            name: "Samantha",
            identifier: "com.apple.voice.compact.en-US.Samantha",
            language: "en-US"
        )

        #expect(siri > samantha)
    }
}

@Suite("Speech preferences")
struct SpeechPreferencesTests {
    @Test func exposesRequestedOneToFiveTimesRates() {
        #expect(SpeechRate.allCases.map(\.rawValue) == [1, 1.25, 1.5, 2, 3, 4, 5])
        #expect(SpeechRate.allCases.map(\.displayName) == [
            "1×", "1.25×", "1.5×", "2×", "3×", "4×", "5×"
        ])
    }

    @Test func savesAndRestoresRateAndRejectsUnsupportedValues() {
        let name = "SpeechPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        #expect(SpeechPreferences.rate(from: defaults) == .normal)
        SpeechPreferences.saveRate(.quintuple, to: defaults)
        #expect(SpeechPreferences.rate(from: defaults) == .quintuple)
        defaults.set(9, forKey: SpeechPreferences.rateKey)
        #expect(SpeechPreferences.rate(from: defaults) == .normal)

        defaults.removePersistentDomain(forName: name)
    }
}

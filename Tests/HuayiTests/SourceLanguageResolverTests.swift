import Foundation
import NaturalLanguage
import Testing
@testable import Huayi

@Suite("Source language resolver")
struct SourceLanguageResolverTests {
    @Test func ambiguousChineseUsesSimplifiedSystemScript() {
        let language = SourceLanguageResolver.resolve(
            text: "你好",
            locale: Locale(identifier: "zh_CN"),
            detector: { _ in .traditionalChinese }
        )

        #expect(language?.script?.identifier == "Hans")
    }

    @Test func ambiguousChineseUsesTraditionalSystemScript() {
        let language = SourceLanguageResolver.resolve(
            text: "你好",
            locale: Locale(identifier: "zh_TW"),
            detector: { _ in .simplifiedChinese }
        )

        #expect(language?.script?.identifier == "Hant")
    }

    @Test func explicitSimplifiedTextOverridesTraditionalSystem() {
        let language = SourceLanguageResolver.resolve(
            text: "请把方案发给我",
            locale: Locale(identifier: "zh_TW"),
            detector: { _ in .traditionalChinese }
        )

        #expect(language?.script?.identifier == "Hans")
    }

    @Test func explicitTraditionalTextOverridesSimplifiedSystem() {
        let language = SourceLanguageResolver.resolve(
            text: "請把繁體方案發給我",
            locale: Locale(identifier: "zh_CN"),
            detector: { _ in .simplifiedChinese }
        )

        #expect(language?.script?.identifier == "Hant")
    }

    @Test func nonChineseDetectionIsPreserved() {
        let language = SourceLanguageResolver.resolve(
            text: "Hello",
            locale: Locale(identifier: "zh_CN"),
            detector: { _ in .english }
        )

        #expect(language?.minimalIdentifier == "en")
    }

    @Test func asciiTechnicalTokensAreEnglishDespiteDetectorGuess() {
        for token in ["NL", "JA", "XYZQ", "K8s", "CI/CD", "UTF-8", "C++", "C#"] {
            let language = SourceLanguageResolver.resolve(
                text: token,
                locale: Locale(identifier: "zh_CN"),
                detector: { _ in .dutch }
            )

            #expect(language?.minimalIdentifier == "en", "\(token) should be English")
        }
    }

    @Test func nonLatinScriptsStillUseLanguageDetector() {
        let samples: [(String, NLLanguage, String)] = [
            ("GPUとは", .japanese, "ja"),
            ("AI是什么", .simplifiedChinese, "zh"),
            ("GPU란", .korean, "ko")
        ]

        for (text, detected, expected) in samples {
            let language = SourceLanguageResolver.resolve(
                text: text,
                locale: Locale(identifier: "zh_CN"),
                detector: { _ in detected }
            )

            #expect(language?.minimalIdentifier == expected)
        }
    }
}

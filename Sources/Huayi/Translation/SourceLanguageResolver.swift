import Foundation
import NaturalLanguage

struct SourceLanguageResolver {
    typealias Detector = (_ text: String) -> NLLanguage?

    static func resolve(
        text: String,
        locale: Locale = .current,
        detector: Detector = NLLanguageRecognizer.dominantLanguage(for:)
    ) -> Locale.Language? {
        if isLikelyEnglishTechnicalToken(text) {
            return Locale.Language(identifier: "en")
        }

        guard let detected = detector(text), detected != .undetermined else {
            return nil
        }

        guard detected == .simplifiedChinese || detected == .traditionalChinese else {
            return Locale.Language(identifier: detected.rawValue)
        }

        let simplified = text.applyingTransform(
            StringTransform("Hant-Hans"),
            reverse: false
        ) ?? text
        let traditional = text.applyingTransform(
            StringTransform("Hans-Hant"),
            reverse: false
        ) ?? text
        let hasTraditionalEvidence = simplified != text
        let hasSimplifiedEvidence = traditional != text

        if hasSimplifiedEvidence && !hasTraditionalEvidence {
            return Locale.Language(identifier: "zh-Hans")
        }
        if hasTraditionalEvidence && !hasSimplifiedEvidence {
            return Locale.Language(identifier: "zh-Hant")
        }

        switch preferredChineseScript(in: locale) {
        case "Hant":
            return Locale.Language(identifier: "zh-Hant")
        case "Hans":
            return Locale.Language(identifier: "zh-Hans")
        default:
            return Locale.Language(identifier: detected.rawValue)
        }
    }

    static func isLikelyEnglishTechnicalToken(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...32).contains(trimmed.count) else { return false }

        var containsASCIILetter = false
        for scalar in trimmed.unicodeScalars {
            switch scalar.value {
            case 65...90, 97...122:
                containsASCIILetter = true
            case 48...57, 35, 38, 43, 45, 46, 47, 95:
                continue
            default:
                return false
            }
        }
        return containsASCIILetter
    }

    private static func preferredChineseScript(in locale: Locale) -> String? {
        if let script = locale.language.script?.identifier {
            return script
        }
        switch locale.region?.identifier {
        case "TW", "HK", "MO":
            return "Hant"
        case "CN", "SG", "MY":
            return "Hans"
        default:
            return nil
        }
    }
}

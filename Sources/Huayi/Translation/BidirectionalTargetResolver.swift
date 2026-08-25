import Foundation

struct BidirectionalTranslationDirection: Equatable, Sendable {
    let partner: LanguageOption
    let actualTarget: LanguageOption
    let label: String
}

enum BidirectionalTargetResolver {
    static let simplifiedChinese = LanguageOption(
        identifier: "zh-Hans",
        localizedName: "中文",
        englishName: "Chinese, Simplified"
    )

    static func resolve(
        source: Locale.Language?,
        partner: LanguageOption
    ) -> BidirectionalTranslationDirection {
        let translatesToChinese = source.map {
            languageCode(of: $0) == languageCode(of: partner.language)
        } ?? false
        let target = translatesToChinese ? simplifiedChinese : partner
        let sourceName = translatesToChinese
            ? partner.localizedName
            : source.map(localizedSourceName) ?? "中文"
        return BidirectionalTranslationDirection(
            partner: partner,
            actualTarget: target,
            label: "\(sourceName) → \(target.localizedName)"
        )
    }

    private static func languageCode(of language: Locale.Language) -> String {
        language.minimalIdentifier
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased() ?? language.minimalIdentifier.lowercased()
    }

    private static func localizedSourceName(_ language: Locale.Language) -> String {
        switch languageCode(of: language) {
        case "zh": "中文"
        case "en": "英语"
        case "ja": "日语"
        case "ko": "韩语"
        default: "原文"
        }
    }
}

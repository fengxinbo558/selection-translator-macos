import Foundation
import Testing
@testable import Huayi

@Suite("Bidirectional target resolver")
struct BidirectionalTargetResolverTests {
    private let english = LanguageOption(
        identifier: "en",
        localizedName: "英语",
        englishName: "English"
    )

    @Test func chineseTargetsSelectedPartner() {
        let direction = BidirectionalTargetResolver.resolve(
            source: Locale.Language(identifier: "zh-Hans"),
            partner: english
        )

        #expect(direction.actualTarget == english)
        #expect(direction.label == "中文 → 英语")
    }

    @Test func selectedPartnerTargetsChinese() {
        let direction = BidirectionalTargetResolver.resolve(
            source: Locale.Language(identifier: "en-US"),
            partner: english
        )

        #expect(direction.actualTarget.identifier == "zh-Hans")
        #expect(direction.label == "英语 → 中文")
    }

    @Test func unknownSourceStillTargetsSelectedPartner() {
        let direction = BidirectionalTargetResolver.resolve(source: nil, partner: english)

        #expect(direction.actualTarget == english)
    }

    @Test func englishTechnicalTokenUsesItsActualSourceNameForJapaneseTarget() {
        let japanese = LanguageOption(
            identifier: "ja",
            localizedName: "日语",
            englishName: "Japanese"
        )

        let direction = BidirectionalTargetResolver.resolve(
            source: Locale.Language(identifier: "en"),
            partner: japanese
        )

        #expect(direction.actualTarget == japanese)
        #expect(direction.label == "英语 → 日语")
    }
}

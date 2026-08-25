import Foundation
import Testing
import Translation
@testable import Huayi

@MainActor
@Suite("Translation availability cache")
struct TranslationAvailabilityCacheTests {
    @Test func installedStatusIsCached() async {
        var loadCount = 0
        let cache = TranslationAvailabilityCache { _, _ in
            loadCount += 1
            return .installed
        }
        let source = Locale.Language(identifier: "zh-Hans")
        let target = Locale.Language(identifier: "en")

        _ = await cache.status(from: source, to: target)
        _ = await cache.status(from: source, to: target)

        #expect(loadCount == 1)
    }

    @Test func supportedStatusIsRecheckedBecauseInstallationCanChange() async {
        var loadCount = 0
        let cache = TranslationAvailabilityCache { _, _ in
            loadCount += 1
            return .supported
        }
        let source = Locale.Language(identifier: "zh-Hant")
        let target = Locale.Language(identifier: "en")

        _ = await cache.status(from: source, to: target)
        _ = await cache.status(from: source, to: target)

        #expect(loadCount == 2)
    }
}

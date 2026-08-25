import Foundation
import Testing
@testable import Huayi

@MainActor
@Suite("Selection replacement session")
struct SelectionReplacementSessionTests {
    @Test func consecutiveReplacementsTrackCurrentTextAndRange() async throws {
        let snapshot = SelectionSnapshot(
            processIdentifier: 1,
            bundleIdentifier: "test.app",
            focusedElement: nil,
            originalText: "你好",
            selectedRange: CFRange(location: 6, length: 2),
            replacementCapability: .direct,
            capturedAt: Date()
        )
        var expectedTexts: [String] = []
        var ranges: [CFRange?] = []
        let session = SelectionReplacementSession(snapshot: snapshot) {
            translatedText, expectedText, range in
            expectedTexts.append(expectedText)
            ranges.append(range)
            return range.map {
                CFRange(location: $0.location, length: translatedText.utf16.count)
            }
        }

        try await session.replace(with: "Hello")
        try await session.replace(with: "こんにちは")

        #expect(expectedTexts == ["你好", "Hello"])
        #expect(ranges[0]?.location == 6)
        #expect(ranges[0]?.length == 2)
        #expect(ranges[1]?.location == 6)
        #expect(ranges[1]?.length == 5)
    }
}

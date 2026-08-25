import Testing
@testable import Huayi

@Suite("Selection fallback policy")
struct SelectionFallbackPolicyTests {
    @Test func opensManualInputForUnreadableSelection() {
        #expect(SelectionFallbackPolicy.shouldOpenManualInput(
            after: .accessibilityPermission
        ))
        #expect(SelectionFallbackPolicy.shouldOpenManualInput(
            after: .noSelection
        ))
    }

    @Test func protectedContentKeepsItsOwnError() {
        #expect(!SelectionFallbackPolicy.shouldOpenManualInput(
            after: .protectedContent
        ))
    }

    @Test func unrelatedErrorsKeepTheirOwnError() {
        #expect(!SelectionFallbackPolicy.shouldOpenManualInput(
            after: .translationFailed
        ))
    }
}

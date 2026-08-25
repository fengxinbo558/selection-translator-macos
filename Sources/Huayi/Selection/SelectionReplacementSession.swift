import ApplicationServices
import Foundation

@MainActor
final class SelectionReplacementSession {
    typealias Executor = @MainActor (
        _ translatedText: String,
        _ expectedSelectedText: String,
        _ selectedRange: CFRange?
    ) async throws -> CFRange?

    private let executor: Executor
    private var expectedSelectedText: String
    private var selectedRange: CFRange?

    init(snapshot: SelectionSnapshot, selectionService: SelectionService) {
        expectedSelectedText = snapshot.originalText
        selectedRange = snapshot.selectedRange
        executor = { translatedText, expectedSelectedText, selectedRange in
            try await selectionService.replaceSelection(
                with: translatedText,
                snapshot: snapshot,
                expectedSelectedText: expectedSelectedText,
                selectedRange: selectedRange
            )
        }
    }

    init(snapshot: SelectionSnapshot, executor: @escaping Executor) {
        expectedSelectedText = snapshot.originalText
        selectedRange = snapshot.selectedRange
        self.executor = executor
    }

    func replace(with translatedText: String) async throws {
        selectedRange = try await executor(
            translatedText,
            expectedSelectedText,
            selectedRange
        )
        expectedSelectedText = translatedText
    }
}

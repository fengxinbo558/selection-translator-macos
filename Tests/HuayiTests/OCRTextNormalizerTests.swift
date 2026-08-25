import CoreGraphics
import Testing
@testable import Huayi

@Suite("OCR text normalizer")
struct OCRTextNormalizerTests {
    @Test func sortsVisualLinesAndJoinsCJK() {
        let blocks = [
            block("世界", x: 0.1, y: 0.6),
            block("你好", x: 0.1, y: 0.8),
        ]

        #expect(OCRTextNormalizer.normalize(blocks) == "你好世界")
    }

    @Test func repairsEnglishHyphenation() {
        let blocks = [
            block("trans-", x: 0.1, y: 0.8),
            block("lation works", x: 0.1, y: 0.6),
        ]

        #expect(OCRTextNormalizer.normalize(blocks) == "translation works")
    }

    @Test func truncatesByUTF16Units() {
        let text = String(repeating: "a", count: OCRTextNormalizer.maximumUTF16Length + 8)
        let result = OCRTextNormalizer.normalize([block(text, x: 0, y: 0.8)])

        #expect(result.utf16.count == OCRTextNormalizer.maximumUTF16Length)
    }

    private func block(_ text: String, x: CGFloat, y: CGFloat) -> OCRTextBlock {
        OCRTextBlock(
            text: text,
            confidence: 1,
            boundingBox: CGRect(x: x, y: y, width: 0.5, height: 0.08)
        )
    }
}

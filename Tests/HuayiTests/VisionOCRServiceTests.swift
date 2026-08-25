import AppKit
import Testing
@testable import Huayi

@MainActor
@Suite("Vision OCR service")
struct VisionOCRServiceTests {
    @Test func recognizesRenderedEnglishText() async throws {
        let image = NSImage(size: NSSize(width: 640, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 640, height: 180).fill()
        "Hello Translation".draw(
            at: NSPoint(x: 36, y: 64),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 42, weight: .medium),
                .foregroundColor: NSColor.black,
            ]
        )
        image.unlockFocus()
        var proposed = NSRect(origin: .zero, size: image.size)
        let cgImage = try #require(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))

        let blocks = try await VisionOCRService().recognize(cgImage)
        let text = OCRTextNormalizer.normalize(blocks)

        #expect(text.localizedCaseInsensitiveContains("Hello"))
        #expect(text.localizedCaseInsensitiveContains("Translation"))
    }
}

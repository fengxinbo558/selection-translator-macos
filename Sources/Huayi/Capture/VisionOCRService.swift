import CoreGraphics
import Foundation
@preconcurrency import Vision

struct OCRTextBlock: Sendable {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

enum VisionOCRServiceError: Error {
    case noText
}

actor VisionOCRService {
    func recognize(_ image: CGImage) throws -> [OCRTextBlock] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.008

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let blocks = (request.results ?? []).compactMap { observation -> OCRTextBlock? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRTextBlock(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
        }
        guard !blocks.isEmpty else { throw VisionOCRServiceError.noText }
        return blocks
    }
}

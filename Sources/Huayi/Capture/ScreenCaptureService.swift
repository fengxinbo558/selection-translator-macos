import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum ScreenCaptureServiceError: Error {
    case displayUnavailable
    case emptyImage
}

actor ScreenCaptureService {
    func capture(region: ScreenRegion) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw ScreenCaptureServiceError.displayUnavailable
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )
        let displayBounds = CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height))
        let sourceRect = region.sourceRect.intersection(displayBounds)
        guard !sourceRect.isNull, sourceRect.width >= 2, sourceRect.height >= 2 else {
            throw ScreenCaptureServiceError.emptyImage
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = max(2, Int((sourceRect.width * scale).rounded()))
        configuration.height = max(2, Int((sourceRect.height * scale).rounded()))
        configuration.captureResolution = .best
        configuration.showsCursor = false

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: ScreenCaptureServiceError.emptyImage)
                }
            }
        }
    }
}

import Foundation

enum CaptureSessionState: Equatable {
    case idle
    case selecting
    case capturing
    case recognizing
    case cancelled
    case failed
}

@MainActor
final class CaptureSessionCoordinator {
    private let overlayController = CaptureOverlayController()
    private let captureService = ScreenCaptureService()
    private let ocrService = VisionOCRService()
    private var task: Task<Void, Never>?
    private var requestID = 0

    private(set) var state: CaptureSessionState = .idle
    var onStateChange: ((CaptureSessionState) -> Void)?
    var onRecognizedText: ((String) -> Void)?
    var onFailure: ((Error) -> Void)?

    func start() {
        if state == .selecting {
            cancel()
            return
        }
        cancelPendingTask()
        requestID &+= 1
        let id = requestID
        updateState(.selecting)
        overlayController.begin { [weak self] region in
            guard let self, id == requestID else { return }
            guard let region else {
                updateState(.cancelled)
                updateState(.idle)
                return
            }
            process(region, requestID: id)
        }
    }

    func cancel() {
        requestID &+= 1
        overlayController.cancel()
        cancelPendingTask()
        updateState(.cancelled)
        updateState(.idle)
    }

    private func process(_ region: ScreenRegion, requestID id: Int) {
        updateState(.capturing)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await captureService.capture(region: region)
                guard !Task.isCancelled, id == requestID else { return }
                updateState(.recognizing)
                let blocks = try await ocrService.recognize(image)
                guard !Task.isCancelled, id == requestID else { return }
                let text = OCRTextNormalizer.normalize(blocks)
                guard !text.isEmpty else { throw VisionOCRServiceError.noText }
                updateState(.idle)
                onRecognizedText?(text)
            } catch is CancellationError {
                guard id == requestID else { return }
                updateState(.cancelled)
                updateState(.idle)
            } catch {
                guard id == requestID else { return }
                updateState(.failed)
                onFailure?(error)
                updateState(.idle)
            }
        }
    }

    private func cancelPendingTask() {
        task?.cancel()
        task = nil
    }

    private func updateState(_ value: CaptureSessionState) {
        state = value
        onStateChange?(value)
    }
}

import AppKit
import CoreGraphics

struct ScreenRegion: Sendable {
    let displayID: CGDirectDisplayID
    /// Display-local logical coordinates with a top-left origin.
    let sourceRect: CGRect
}

@MainActor
final class CaptureOverlayController {
    private var panel: CapturePanel?
    private var completion: ((ScreenRegion?) -> Void)?

    var isSelecting: Bool { panel != nil }

    func begin(completion: @escaping (ScreenRegion?) -> Void) {
        cancel()
        guard let screen = screenUnderPointer(),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber
        else {
            completion(nil)
            return
        }

        let displayID = CGDirectDisplayID(number.uint32Value)
        let selectionView = CaptureSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        selectionView.onFinish = { [weak self] rect in
            guard let self else { return }
            let result = rect.map { ScreenRegion(displayID: displayID, sourceRect: $0) }
            finish(with: result)
        }

        let panel = CapturePanel(
            contentRect: screen.frame,
            styleMask: PanelPresentationPolicy.borderlessStyleMask,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .transient,
        ]
        panel.isReleasedWhenClosed = false
        panel.contentView = selectionView
        panel.onCancel = { [weak self] in self?.finish(with: nil) }

        self.completion = completion
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSCursor.crosshair.push()
    }

    func cancel() {
        guard panel != nil else { return }
        finish(with: nil)
    }

    private func finish(with region: ScreenRegion?) {
        guard let completion else { return }
        self.completion = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        NSCursor.pop()
        completion(region)
    }

    private func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }
}

private final class CapturePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }
}

private final class CaptureSelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = clamped(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = clamped(convert(event.locationInWindow, from: nil))
        guard let selection = selectionRect, selection.width >= 4, selection.height >= 4 else {
            onFinish?(nil)
            return
        }
        let topLeftRect = CGRect(
            x: selection.minX,
            y: bounds.height - selection.maxY,
            width: selection.width,
            height: selection.height
        )
        onFinish?(topLeftRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let selectionRect else {
            drawInstruction()
            return
        }

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: selectionRect).addClip()
        NSColor.clear.setFill()
        selectionRect.fill(using: .copy)
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(roundedRect: selectionRect, xRadius: 4, yRadius: 4)
        border.lineWidth = 2
        border.stroke()
        drawInstruction()
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func drawInstruction() {
        let text = "拖动框选文字 · Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.65),
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: bounds.midX - size.width / 2 - 10,
            y: bounds.maxY - 64,
            width: size.width + 20,
            height: size.height + 10
        )
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        text.draw(
            at: CGPoint(x: rect.minX + 10, y: rect.minY + 5),
            withAttributes: attributes.merging([.backgroundColor: NSColor.clear]) { _, new in new }
        )
    }
}

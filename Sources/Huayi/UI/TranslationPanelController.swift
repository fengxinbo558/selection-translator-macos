import AppKit
import SwiftUI

@MainActor
final class TranslationPanelController: NSObject, NSWindowDelegate {
    private var panel: NSWindow?
    private var retainedModel: AnyObject?
    private var noticeTask: Task<Void, Never>?

    var onClose: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    func show(model: TranslationPanelModel) {
        close()
        retainedModel = model

        model.onSuccess = { [weak self] in self?.close() }
        model.onCancel = { [weak self] in self?.close() }

        let size = NSSize(width: 460, height: 470)
        let panel = QuickPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: PanelPresentationPolicy.manualStyleMask,
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        PanelPresentationPolicy.apply(to: panel)
        panel.title = "划译"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .none
            : .utilityWindow
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentViewController = NSHostingController(
            rootView: TranslationPanelView(model: model)
        )
        panel.setFrameOrigin(position(for: size))

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        if model.isManualEntry {
            DispatchQueue.main.async { [weak panel] in
                guard let panel,
                      let textView = panel.contentView?.firstDescendant(of: NSTextView.self)
                else { return }
                panel.makeFirstResponder(textView)
            }
        }
    }

    func showCompact(model: CompactTranslationModel) {
        close()
        retainedModel = model
        model.onClose = { [weak self] in self?.close() }

        let size = NSSize(width: 360, height: 208)
        let panel = QuickPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: PanelPresentationPolicy.borderlessStyleMask,
            backing: .buffered,
            defer: false
        )
        PanelPresentationPolicy.apply(to: panel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .none
            : .utilityWindow
        panel.contentViewController = NSHostingController(
            rootView: CompactTranslationView(model: model)
        )
        panel.setFrameOrigin(position(for: size))

        self.panel = panel
        panel.orderFrontRegardless()
    }

    func close() {
        noticeTask?.cancel()
        noticeTask = nil
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
        retainedModel = nil
        onClose?()
    }

    func showNotice(_ message: String) {
        close()
        let size = NSSize(width: 380, height: 112)
        let panel = QuickPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        PanelPresentationPolicy.apply(to: panel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: TranslationNoticeView(message: message) { [weak self] in self?.close() }
        )
        panel.setFrameOrigin(position(for: size))
        self.panel = panel
        panel.orderFrontRegardless()

        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    func showActionNotice(
        title: String,
        message: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        close()
        let size = NSSize(width: 430, height: 190)
        let panel = QuickPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        PanelPresentationPolicy.apply(to: panel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: TranslationActionNoticeView(
                title: title,
                message: message,
                primaryTitle: primaryTitle,
                primaryAction: primaryAction,
                secondaryTitle: secondaryTitle,
                secondaryAction: secondaryAction,
                close: { [weak self] in self?.close() }
            )
        )
        panel.setFrameOrigin(position(for: size))
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func showLoading(_ message: String) {
        close()
        let size = NSSize(width: 340, height: 96)
        let panel = QuickPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        PanelPresentationPolicy.apply(to: panel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: TranslationLoadingView(message: message)
        )
        panel.setFrameOrigin(position(for: size))
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        retainedModel = nil
    }

    private func position(for size: NSSize) -> NSPoint {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return cursor }

        var x = cursor.x + 12
        var y = cursor.y - size.height - 12
        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        if y < visibleFrame.minY + 8 {
            y = min(cursor.y + 12, visibleFrame.maxY - size.height - 8)
        }
        return NSPoint(x: x, y: y)
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) { return match }
        }
        return nil
    }
}

private struct TranslationLoadingView: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 13.5, weight: .medium))
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 340, height: 96)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
    }
}

private struct TranslationNoticeView: View {
    let message: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "character.bubble")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13.5, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(18)
        .frame(width: 380, height: 112)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
        .onExitCommand(perform: close)
    }
}

private struct TranslationActionNoticeView: View {
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
            }
            HStack {
                Spacer()
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                }
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 430, height: 190)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
        .onExitCommand(perform: close)
    }
}

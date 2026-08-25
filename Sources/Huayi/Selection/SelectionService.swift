import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

@MainActor
final class SelectionService {
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func captureSelection() async throws -> SelectionSnapshot {
        guard hasAccessibilityPermission else {
            throw AppError.accessibilityPermission
        }
        guard let application = NSWorkspace.shared.frontmostApplication else {
            throw AppError.noSelection
        }

        let focusedElement = try focusedUIElement()
        if isProtected(focusedElement) {
            throw AppError.protectedContent
        }

        let selectedRange = selectedRange(of: focusedElement)
        let capability = replacementCapability(of: focusedElement)
        if let text: String = attribute(kAXSelectedTextAttribute, of: focusedElement),
           !text.isEmpty {
            return SelectionSnapshot(
                processIdentifier: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                focusedElement: focusedElement,
                originalText: text,
                selectedRange: selectedRange,
                replacementCapability: capability,
                capturedAt: Date()
            )
        }

        let text = try await readSelectionThroughClipboard()
        return SelectionSnapshot(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            focusedElement: focusedElement,
            originalText: text,
            selectedRange: selectedRange,
            replacementCapability: capability,
            capturedAt: Date()
        )
    }

    func replaceSelection(with translatedText: String, snapshot: SelectionSnapshot) async throws {
        _ = try await replaceSelection(
            with: translatedText,
            snapshot: snapshot,
            expectedSelectedText: snapshot.originalText,
            selectedRange: snapshot.selectedRange
        )
    }

    @discardableResult
    func replaceSelection(
        with translatedText: String,
        snapshot: SelectionSnapshot,
        expectedSelectedText: String,
        selectedRange: CFRange?
    ) async throws -> CFRange? {
        guard let application = NSRunningApplication(
            processIdentifier: snapshot.processIdentifier
        ) else {
            throw AppError.selectionChanged
        }

        application.activate()
        try await Task.sleep(for: .milliseconds(140))

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.processIdentifier else {
            throw AppError.selectionChanged
        }
        let currentFocusedElement = try focusedUIElement()
        if let originalElement = snapshot.focusedElement,
           !CFEqual(originalElement, currentFocusedElement) {
            throw AppError.selectionChanged
        }
        if let currentText: String = attribute(kAXSelectedTextAttribute, of: currentFocusedElement),
           currentText != expectedSelectedText {
            throw AppError.selectionChanged
        }

        if expectedSelectedText != snapshot.originalText,
           attribute(kAXSelectedTextAttribute, of: currentFocusedElement) as String? == nil {
            throw AppError.selectionChanged
        }

        let replacementRange = selectedRange.map {
            CFRange(location: $0.location, length: translatedText.utf16.count)
        }

        switch snapshot.replacementCapability {
        case .direct:
            let status = AXUIElementSetAttributeValue(
                currentFocusedElement,
                kAXSelectedTextAttribute as CFString,
                translatedText as CFString
            )
            if status != .success {
                try await pasteReplacement(translatedText)
            }
            restoreSelection(replacementRange, on: currentFocusedElement)
            return replacementRange
        case .paste:
            try await pasteReplacement(translatedText)
            restoreSelection(replacementRange, on: currentFocusedElement)
            return replacementRange
        case .copyOnly:
            throw AppError.notEditable
        }
    }

    func copyToClipboard(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw AppError.clipboardUnavailable
        }
    }

    private func focusedUIElement() throws -> AXUIElement {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard status == .success, let value else {
            throw AppError.noSelection
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &value
            ) == .success,
            let value
        else {
            return nil
        }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private func replacementCapability(of element: AXUIElement) -> ReplacementCapability {
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success, settable.boolValue {
            return .direct
        }

        let role: String? = attribute(kAXRoleAttribute, of: element)
        let editableRoles = [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole]
        return role.map(editableRoles.contains) == true ? .paste : .copyOnly
    }

    private func isProtected(_ element: AXUIElement) -> Bool {
        let subrole: String? = attribute(kAXSubroleAttribute, of: element)
        return subrole == kAXSecureTextFieldSubrole
    }

    private func restoreSelection(_ range: CFRange?, on element: AXUIElement) {
        guard var range,
              let value = AXValueCreate(.cfRange, &range)
        else { return }
        AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        )
    }

    private func readSelectionThroughClipboard() async throws -> String {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        defer { snapshot.restore(to: pasteboard) }

        pasteboard.clearContents()
        let initialChangeCount = pasteboard.changeCount
        postCommandKey(CGKeyCode(kVK_ANSI_C))

        for _ in 0..<25 {
            try await Task.sleep(for: .milliseconds(12))
            if pasteboard.changeCount != initialChangeCount,
               let text = pasteboard.string(forType: .string),
               !text.isEmpty {
                return text
            }
        }
        throw AppError.noSelection
    }

    private func pasteReplacement(_ text: String) async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(to: pasteboard)
            throw AppError.clipboardUnavailable
        }

        postCommandKey(CGKeyCode(kVK_ANSI_V))
        try await Task.sleep(for: .milliseconds(220))
        snapshot.restore(to: pasteboard)
    }

    private func postCommandKey(_ keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

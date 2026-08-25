import ApplicationServices
import Foundation

enum ReplacementCapability: Sendable {
    case direct
    case paste
    case copyOnly
}

struct SelectionSnapshot {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let focusedElement: AXUIElement?
    let originalText: String
    let selectedRange: CFRange?
    let replacementCapability: ReplacementCapability
    let capturedAt: Date
}

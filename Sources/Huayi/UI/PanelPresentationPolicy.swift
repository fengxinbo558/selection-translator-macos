import AppKit

enum PanelPresentationPolicy {
    static let activationPolicy = NSApplication.ActivationPolicy.accessory
    static let level = NSWindow.Level.statusBar
    static let manualStyleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .fullSizeContentView,
        .nonactivatingPanel,
    ]
    static let borderlessStyleMask: NSWindow.StyleMask = [
        .borderless,
        .nonactivatingPanel,
    ]
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .canJoinAllApplications,
        .fullScreenAuxiliary,
        .transient,
    ]

    @MainActor
    static func apply(to window: NSWindow) {
        if let panel = window as? NSPanel {
            panel.isFloatingPanel = true
            panel.worksWhenModal = true
            panel.becomesKeyOnlyIfNeeded = false
        }
        // isFloatingPanel changes the level to .floating, so set our overlay
        // level after configuring the NSPanel behavior.
        window.level = level
        window.collectionBehavior = collectionBehavior
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
    }
}

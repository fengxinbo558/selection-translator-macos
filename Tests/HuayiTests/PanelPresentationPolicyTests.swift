import AppKit
import Testing
@testable import Huayi

@MainActor
@Suite("Panel presentation policy")
struct PanelPresentationPolicyTests {
    @Test func usesAccessoryNonactivatingPresentation() {
        #expect(PanelPresentationPolicy.activationPolicy == .accessory)
        #expect(PanelPresentationPolicy.manualStyleMask.contains(.nonactivatingPanel))
        #expect(PanelPresentationPolicy.borderlessStyleMask.contains(.nonactivatingPanel))
    }

    @Test func joinsSpacesAndOtherApplicationsFullScreen() {
        let behavior = PanelPresentationPolicy.collectionBehavior

        #expect(behavior.contains(.canJoinAllSpaces))
        #expect(behavior.contains(.canJoinAllApplications))
        #expect(behavior.contains(.fullScreenAuxiliary))
        #expect(behavior.contains(.transient))
    }

    @Test func appliesVisibleOverlayBehavior() {
        let panel = NSPanel()

        PanelPresentationPolicy.apply(to: panel)

        #expect(panel.level == .statusBar)
        #expect(panel.collectionBehavior == PanelPresentationPolicy.collectionBehavior)
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.isExcludedFromWindowsMenu)
        #expect(panel.isFloatingPanel)
        #expect(panel.worksWhenModal)
        #expect(!panel.becomesKeyOnlyIfNeeded)
    }
}

import AppKit
import SwiftUI

@main
struct HuayiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    appDelegate.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Huayi is a menu-bar overlay utility. Keeping it out of the normal
        // Dock/application activation flow prevents a shortcut from switching
        // the user back to the Space where Huayi was first launched.
        NSApp.setActivationPolicy(PanelPresentationPolicy.activationPolicy)
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    func showSettings() {
        coordinator.showSettingsWindow()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !ProcessInfo.processInfo.arguments.contains("--show-demo") {
            coordinator.showTranslatorWindow()
        }
        return true
    }
}

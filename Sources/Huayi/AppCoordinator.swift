import AppKit
import Foundation

@MainActor
final class AppCoordinator: NSObject {
    private let shortcutManager = GlobalShortcutManager()
    private let selectionService = SelectionService()
    private let languageCatalog = LanguageCatalog()
    private let availabilityCache = TranslationAvailabilityCache()
    private let panelController = TranslationPanelController()
    private let screenCapturePermissionService = ScreenCapturePermissionService()
    private let captureCoordinator = CaptureSessionCoordinator()
    private let aiTranslationService = AITranslationService()
    private let credentialStore = KeychainCredentialStore()

    private var statusItem: NSStatusItem?
    private var settingsController: SettingsWindowController?
    private var activeTask: Task<Void, Never>?
    private var isObservingApplicationChanges = false
    private var sourceProcessIdentifier: pid_t?
    private(set) var currentShortcut = ShortcutDefinition.load()
    private(set) var currentScreenshotShortcut = ShortcutDefinition.loadScreenshot()
    private(set) var preferredTargetLanguageIdentifier = TargetLanguagePreference.load()
    private var isSelectionShortcutRegistered = false
    private var isScreenshotShortcutRegistered = false
    private var continueScreenshotAfterPermission = false

    func start() {
        configureStatusItem()
        configureShortcuts()
        configureSettings()
        observeApplicationChanges()
        configureCaptureCoordinator()
        Task { await languageCatalog.loadSupportedLanguages() }
        panelController.onClose = { [weak self] in
            self?.sourceProcessIdentifier = nil
        }
        if ProcessInfo.processInfo.arguments.contains("--show-demo") {
            DispatchQueue.main.async { [weak self] in self?.showDemoPanel() }
        } else {
            DispatchQueue.main.async { [weak self] in self?.showManualTranslator() }
        }
    }

    func stop() {
        activeTask?.cancel()
        shortcutManager.unregister()
        captureCoordinator.cancel()
        if isObservingApplicationChanges {
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            isObservingApplicationChanges = false
        }
        panelController.close()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    func showSettingsWindow() {
        settingsController?.show()
    }

    func showTranslatorWindow() {
        showManualTranslator()
    }

    private func configureShortcuts() {
        shortcutManager.onTrigger = { [weak self] command in
            switch command {
            case .translateSelection:
                self?.translateSelectedText()
            case .captureAndTranslate:
                self?.captureAndTranslate()
            }
        }
        do {
            try shortcutManager.register(currentShortcut, for: .translateSelection)
            isSelectionShortcutRegistered = true
        } catch {
            isSelectionShortcutRegistered = false
        }
        do {
            try shortcutManager.register(currentScreenshotShortcut, for: .captureAndTranslate)
            isScreenshotShortcutRegistered = true
        } catch {
            isScreenshotShortcutRegistered = false
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "character.bubble",
                accessibilityDescription: "划译"
            )
            button.toolTip = "划译"
        }
        item.menu = makeStatusMenu()
        statusItem = item
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let translate = NSMenuItem(
            title: "翻译选中文字    \(currentShortcut.displayString)",
            action: #selector(translateMenuItem),
            keyEquivalent: ""
        )
        translate.target = self
        menu.addItem(translate)

        let capture = NSMenuItem(
            title: "截图翻译    \(currentScreenshotShortcut.displayString)",
            action: #selector(captureMenuItem),
            keyEquivalent: ""
        )
        capture.target = self
        menu.addItem(capture)

        let openTranslator = NSMenuItem(
            title: "输入文字翻译…",
            action: #selector(openTranslatorMenuItem),
            keyEquivalent: ""
        )
        openTranslator.target = self
        menu.addItem(openTranslator)
        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "设置…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(
            title: "退出划译",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func configureSettings() {
        let model = SettingsModel(
            shortcut: currentShortcut,
            screenshotShortcut: currentScreenshotShortcut,
            isSelectionShortcutRegistered: isSelectionShortcutRegistered,
            isScreenshotShortcutRegistered: isScreenshotShortcutRegistered,
            hasAccessibilityPermission: selectionService.hasAccessibilityPermission,
            hasScreenCapturePermission: screenCapturePermissionService.hasPermission,
            changeShortcut: { [weak self] shortcut in
                self?.changeShortcut(to: shortcut, command: .translateSelection)
                    ?? .failure(.unavailable(-1))
            },
            changeScreenshotShortcut: { [weak self] shortcut in
                self?.changeShortcut(to: shortcut, command: .captureAndTranslate)
                    ?? .failure(.unavailable(-1))
            },
            requestPermission: { [weak self] in self?.requestAccessibilityPermission() },
            requestScreenCapturePermission: { [weak self] in
                self?.requestScreenCapturePermission()
            },
            permissionStatus: { [weak self] in
                self?.selectionService.hasAccessibilityPermission == true
            },
            screenCapturePermissionStatus: { [weak self] in
                self?.screenCapturePermissionService.hasPermission == true
            },
            openTranslator: { [weak self] in self?.showManualTranslator() },
            startScreenshotTranslation: { [weak self] in self?.captureAndTranslate() },
            preferredTargetLanguageIdentifier: preferredTargetLanguageIdentifier,
            changeTargetLanguage: { [weak self] identifier in
                self?.changeTargetLanguage(to: identifier)
            }
        )
        settingsController = SettingsWindowController(model: model, catalog: languageCatalog)
    }

    private func changeShortcut(
        to shortcut: ShortcutDefinition,
        command: ShortcutCommand
    ) -> Result<Void, GlobalShortcutError> {
        do {
            try shortcutManager.register(shortcut, for: command)
            switch command {
            case .translateSelection:
                shortcut.save()
                currentShortcut = shortcut
                isSelectionShortcutRegistered = true
            case .captureAndTranslate:
                shortcut.saveScreenshot()
                currentScreenshotShortcut = shortcut
                isScreenshotShortcutRegistered = true
            }
            statusItem?.menu = makeStatusMenu()
            return .success(())
        } catch let error as GlobalShortcutError {
            return .failure(error)
        } catch {
            return .failure(.unavailable(-1))
        }
    }

    private func changeTargetLanguage(to identifier: String) {
        preferredTargetLanguageIdentifier = identifier
        TargetLanguagePreference.save(identifier)
    }

    private func translateSelectedText() {
        activeTask?.cancel()
        sourceProcessIdentifier = nil
        panelController.showLoading("正在读取选中文字…")
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await selectionService.captureSelection()
                guard !Task.isCancelled else { return }

                await languageCatalog.loadSupportedLanguages()
                guard !Task.isCancelled else { return }
                guard let target = preferredTargetLanguage() else {
                    throw AppError.languageUnavailable
                }

                let replacementSession = SelectionReplacementSession(
                    snapshot: snapshot,
                    selectionService: selectionService
                )
                let model = CompactTranslationModel(
                    snapshot: snapshot,
                    catalog: languageCatalog,
                    replaceAction: { text in
                        try await replacementSession.replace(with: text)
                    },
                    copyAction: { [weak self] text in
                        guard let self else { throw AppError.clipboardUnavailable }
                        try selectionService.copyToClipboard(text)
                    },
                    cloudTranslation: makeCloudTranslation(),
                    availabilityChecker: { [weak self] source, target in
                        guard let self else { return .unsupported }
                        return await availabilityCache.status(from: source, to: target)
                    }
                )
                model.onTargetChanged = { [weak self] identifier in
                    self?.changeTargetLanguage(to: identifier)
                }
                model.start(to: target)
                panelController.showCompact(model: model)
                sourceProcessIdentifier = snapshot.processIdentifier
            } catch let error as AppError {
                if !openManualInputIfNeeded(after: error) {
                    handleCaptureError(error)
                }
            } catch {
                panelController.showNotice(AppError.noSelection.userMessage)
            }
        }
    }

    private func preferredTargetLanguage() -> LanguageOption? {
        languageCatalog.options.first {
            $0.identifier.caseInsensitiveCompare(preferredTargetLanguageIdentifier)
                == .orderedSame
        } ?? languageCatalog.options.first {
            $0.identifier.caseInsensitiveCompare(TargetLanguagePreference.defaultIdentifier)
                == .orderedSame
        }
    }

    private func handleCaptureError(_ error: AppError) {
        if error == .accessibilityPermission {
            panelController.showActionNotice(
                title: "浏览器文字暂时读不到",
                message: "可开启辅助功能读取选中文字，或开启屏幕录制后自动改用截图框选。",
                primaryTitle: "打开“辅助功能”设置",
                primaryAction: { [weak self] in self?.requestAccessibilityPermission() },
                secondaryTitle: "开启截图翻译",
                secondaryAction: { [weak self] in self?.requestScreenCapturePermission() }
            )
        } else if error == .noSelection {
            panelController.showActionNotice(
                title: "没有读取到选中的文字",
                message: "部分浏览器不会把选区交给其他应用。开启截图权限后，按 \(currentShortcut.displayString) 会自动进入框选翻译。",
                primaryTitle: "开启截图翻译",
                primaryAction: { [weak self] in self?.requestScreenCapturePermission() },
                secondaryTitle: "打开输入翻译器",
                secondaryAction: { [weak self] in self?.showManualTranslator() }
            )
        } else {
            panelController.showNotice(error.userMessage)
        }
    }

    private func openManualInputIfNeeded(after error: AppError) -> Bool {
        guard SelectionFallbackPolicy.shouldOpenManualInput(after: error) else { return false }
        activeTask = nil
        sourceProcessIdentifier = nil
        showManualTranslator()
        return true
    }

    private func requestAccessibilityPermission() {
        _ = selectionService.requestAccessibilityPermission()
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func requestScreenCapturePermission() {
        _ = screenCapturePermissionService.requestPermission()
        if screenCapturePermissionService.hasPermission {
            continueScreenshotAfterPermission = false
            captureAndTranslate()
        } else {
            continueScreenshotAfterPermission = true
            screenCapturePermissionService.openSystemSettings()
        }
    }

    private func configureCaptureCoordinator() {
        captureCoordinator.onStateChange = { [weak self] state in
            switch state {
            case .capturing:
                self?.panelController.showLoading("正在截取框选区域…")
            case .recognizing:
                self?.panelController.showLoading("正在识别文字…")
            default:
                break
            }
        }
        captureCoordinator.onRecognizedText = { [weak self] text in
            self?.showManualTranslator(prefill: text)
        }
        captureCoordinator.onFailure = { [weak self] error in
            let appError: AppError = error is VisionOCRServiceError
                ? .ocrNoText
                : .screenCaptureFailed
            self?.panelController.showNotice(appError.userMessage)
        }
    }

    private func captureAndTranslate() {
        activeTask?.cancel()
        sourceProcessIdentifier = nil
        guard screenCapturePermissionService.hasPermission else {
            continueScreenshotAfterPermission = true
            panelController.showActionNotice(
                title: "截图翻译需要屏幕录制权限",
                message: "划译只会读取你主动框选的区域，不会在后台录屏。开启后返回划译，再按一次截图快捷键。",
                primaryTitle: "打开系统设置",
                primaryAction: { [weak self] in self?.requestScreenCapturePermission() },
                secondaryTitle: "我已开启，重新检查",
                secondaryAction: { [weak self] in self?.captureAndTranslate() }
            )
            return
        }
        continueScreenshotAfterPermission = false
        panelController.close()
        captureCoordinator.start()
    }

    private func showDemoPanel() {
        activeTask?.cancel()
        panelController.showLoading("正在翻译成默认语言…")
        activeTask = Task { [weak self] in
            guard let self else { return }
            await languageCatalog.loadSupportedLanguages()
            guard let target = preferredTargetLanguage() else {
                panelController.showNotice(AppError.languageUnavailable.userMessage)
                return
            }
            let snapshot = SelectionSnapshot(
                processIdentifier: ProcessInfo.processInfo.processIdentifier,
                bundleIdentifier: Bundle.main.bundleIdentifier,
                focusedElement: nil,
                originalText: "今天下午三点前把方案发给我，我们再一起确认细节。",
                selectedRange: nil,
                replacementCapability: .copyOnly,
                capturedAt: Date()
            )
            let model = CompactTranslationModel(
                snapshot: snapshot,
                catalog: languageCatalog,
                replaceAction: { _ in throw AppError.notEditable },
                copyAction: { [weak self] text in
                    guard let self else { throw AppError.clipboardUnavailable }
                    try selectionService.copyToClipboard(text)
                },
                cloudTranslation: makeCloudTranslation(),
                availabilityChecker: { [weak self] source, target in
                    guard let self else { return .unsupported }
                    return await availabilityCache.status(from: source, to: target)
                }
            )
            model.onTargetChanged = { [weak self] identifier in
                self?.changeTargetLanguage(to: identifier)
            }
            model.start(to: target)
            panelController.showCompact(model: model)
        }
    }

    private func showReadyPanel() {
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            await languageCatalog.loadSupportedLanguages()
            guard let target = preferredTargetLanguage() else {
                panelController.showNotice(AppError.languageUnavailable.userMessage)
                return
            }
            let snapshot = SelectionSnapshot(
                processIdentifier: ProcessInfo.processInfo.processIdentifier,
                bundleIdentifier: Bundle.main.bundleIdentifier,
                focusedElement: nil,
                originalText: "",
                selectedRange: nil,
                replacementCapability: .copyOnly,
                capturedAt: Date()
            )
            let model = CompactTranslationModel(
                snapshot: snapshot,
                catalog: languageCatalog,
                replaceAction: { _ in throw AppError.notEditable },
                copyAction: { [weak self] text in
                    guard let self else { throw AppError.clipboardUnavailable }
                    try selectionService.copyToClipboard(text)
                },
                cloudTranslation: makeCloudTranslation(),
                availabilityChecker: { [weak self] source, target in
                    guard let self else { return .unsupported }
                    return await availabilityCache.status(from: source, to: target)
                }
            )
            model.onTargetChanged = { [weak self] identifier in
                self?.changeTargetLanguage(to: identifier)
            }
            model.start(to: target)
            sourceProcessIdentifier = nil
            panelController.showCompact(model: model)
        }
    }

    private func showManualTranslator(prefill: String = "") {
        let snapshot = SelectionSnapshot(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            focusedElement: nil,
            originalText: prefill,
            selectedRange: nil,
            replacementCapability: .copyOnly,
            capturedAt: Date()
        )
        let model = TranslationPanelModel(
            snapshot: snapshot,
            catalog: languageCatalog,
            replaceAction: { _, _ in throw AppError.notEditable },
            copyAction: { [weak self] text in
                guard let self else { throw AppError.clipboardUnavailable }
                try selectionService.copyToClipboard(text)
            },
            isManualEntry: true,
            initialTargetIdentifier: preferredTargetLanguageIdentifier,
            screenshotShortcutDisplayString: currentScreenshotShortcut.displayString,
            cloudTranslation: makeCloudTranslation(),
            availabilityChecker: { [weak self] source, target in
                guard let self else { return .unsupported }
                return await availabilityCache.status(from: source, to: target)
            }
        )
        model.onOpenSettings = { [weak self] in self?.showSettingsWindow() }
        model.onCaptureScreenshot = { [weak self] in self?.captureAndTranslate() }
        model.onTargetChanged = { [weak self] identifier in
            self?.changeTargetLanguage(to: identifier)
        }
        sourceProcessIdentifier = nil
        panelController.show(model: model)
    }

    private func makeCloudTranslation() -> TranslationPanelModel.CloudTranslation? {
        guard AITranslationPreferences.mode() == .ai,
              AITranslationPreferences.privacyAccepted()
        else { return nil }
        let provider = AITranslationPreferences.provider()
        let model = AITranslationPreferences.model(for: provider)
        let compatibleURL = AITranslationPreferences.compatibleURL()
        let service = aiTranslationService
        let credentialStore = credentialStore
        return { text, target in
            guard let key = try credentialStore.read(provider: provider), !key.isEmpty else {
                throw AITranslationError.missingKey
            }
            let configuration = AITranslationConfiguration(
                provider: provider,
                model: model,
                compatibleURL: compatibleURL,
                apiKey: key
            )
            return await service.streamTranslation(
                text: text,
                targetLanguage: target.localizedName,
                configuration: configuration
            )
        }
    }

    private func observeApplicationChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        isObservingApplicationChanges = true
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        if continueScreenshotAfterPermission,
           screenCapturePermissionService.hasPermission {
            continueScreenshotAfterPermission = false
            captureAndTranslate()
            return
        }
        guard
            panelController.isVisible,
            let sourceProcessIdentifier,
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
        else { return }

        let allowed = [sourceProcessIdentifier, ProcessInfo.processInfo.processIdentifier]
        if !allowed.contains(app.processIdentifier) {
            activeTask?.cancel()
            panelController.close()
        }
    }

    @objc private func translateMenuItem() {
        translateSelectedText()
    }

    @objc private func openTranslatorMenuItem() {
        showManualTranslator()
    }

    @objc private func captureMenuItem() {
        captureAndTranslate()
    }

    @objc private func showSettings() {
        settingsController?.show()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}

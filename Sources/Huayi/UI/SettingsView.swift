import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var shortcut: ShortcutDefinition
    @Published private(set) var screenshotShortcut: ShortcutDefinition
    @Published private(set) var isSelectionShortcutRegistered: Bool
    @Published private(set) var isScreenshotShortcutRegistered: Bool
    @Published private(set) var hasAccessibilityPermission: Bool
    @Published private(set) var hasScreenCapturePermission: Bool
    @Published private(set) var preferredTargetLanguageIdentifier: String
    @Published private(set) var translationMode: TranslationMode
    @Published private(set) var aiProvider: AIProvider
    @Published var aiModel: String
    @Published var compatibleURL: String
    @Published var apiKeyInput = ""
    @Published private(set) var isKeySaved: Bool
    @Published private(set) var aiPrivacyAccepted: Bool
    @Published private(set) var aiStatusMessage: String?
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var generalStatusMessage: String?

    private let changeShortcut: (ShortcutDefinition) -> Result<Void, GlobalShortcutError>
    private let changeScreenshotShortcut: (ShortcutDefinition) -> Result<Void, GlobalShortcutError>
    private let requestPermission: () -> Void
    private let requestScreenCapturePermission: () -> Void
    private let permissionStatus: () -> Bool
    private let screenCapturePermissionStatus: () -> Bool
    private let openTranslator: () -> Void
    private let startScreenshotTranslation: () -> Void
    private let changeTargetLanguage: (String) -> Void
    private let credentialStore = KeychainCredentialStore()
    private let launchAtLoginService = LaunchAtLoginService()

    init(
        shortcut: ShortcutDefinition,
        screenshotShortcut: ShortcutDefinition,
        isSelectionShortcutRegistered: Bool,
        isScreenshotShortcutRegistered: Bool,
        hasAccessibilityPermission: Bool,
        hasScreenCapturePermission: Bool,
        changeShortcut: @escaping (ShortcutDefinition) -> Result<Void, GlobalShortcutError>,
        changeScreenshotShortcut: @escaping (ShortcutDefinition) -> Result<Void, GlobalShortcutError>,
        requestPermission: @escaping () -> Void,
        requestScreenCapturePermission: @escaping () -> Void,
        permissionStatus: @escaping () -> Bool,
        screenCapturePermissionStatus: @escaping () -> Bool,
        openTranslator: @escaping () -> Void,
        startScreenshotTranslation: @escaping () -> Void,
        preferredTargetLanguageIdentifier: String,
        changeTargetLanguage: @escaping (String) -> Void
    ) {
        self.shortcut = shortcut
        self.screenshotShortcut = screenshotShortcut
        self.isSelectionShortcutRegistered = isSelectionShortcutRegistered
        self.isScreenshotShortcutRegistered = isScreenshotShortcutRegistered
        self.hasAccessibilityPermission = hasAccessibilityPermission
        self.hasScreenCapturePermission = hasScreenCapturePermission
        self.changeShortcut = changeShortcut
        self.changeScreenshotShortcut = changeScreenshotShortcut
        self.requestPermission = requestPermission
        self.requestScreenCapturePermission = requestScreenCapturePermission
        self.permissionStatus = permissionStatus
        self.screenCapturePermissionStatus = screenCapturePermissionStatus
        self.openTranslator = openTranslator
        self.startScreenshotTranslation = startScreenshotTranslation
        self.preferredTargetLanguageIdentifier = preferredTargetLanguageIdentifier
        self.changeTargetLanguage = changeTargetLanguage
        let provider = AITranslationPreferences.provider()
        translationMode = AITranslationPreferences.mode()
        aiProvider = provider
        aiModel = AITranslationPreferences.model(for: provider)
        compatibleURL = AITranslationPreferences.compatibleURL()
        isKeySaved = (try? credentialStore.read(provider: provider)) != nil
        aiPrivacyAccepted = AITranslationPreferences.privacyAccepted()
        launchAtLogin = launchAtLoginService.isEnabled
    }

    func updateShortcut(_ candidate: ShortcutDefinition) -> Result<Void, GlobalShortcutError> {
        let result = changeShortcut(candidate)
        if case .success = result {
            shortcut = candidate
            isSelectionShortcutRegistered = true
        }
        return result
    }

    func restoreDefaultShortcut() {
        _ = updateShortcut(.defaultShortcut)
    }

    func updateScreenshotShortcut(
        _ candidate: ShortcutDefinition
    ) -> Result<Void, GlobalShortcutError> {
        let result = changeScreenshotShortcut(candidate)
        if case .success = result {
            screenshotShortcut = candidate
            isScreenshotShortcutRegistered = true
        }
        return result
    }

    func restoreDefaultScreenshotShortcut() {
        _ = updateScreenshotShortcut(.defaultScreenshotShortcut)
    }

    func requestAccessibilityPermission() {
        requestPermission()
        refreshPermission()
    }

    func refreshPermission() {
        hasAccessibilityPermission = permissionStatus()
        hasScreenCapturePermission = screenCapturePermissionStatus()
    }

    func requestScreenPermission() {
        requestScreenCapturePermission()
        refreshPermission()
    }

    func showTranslator() {
        openTranslator()
    }

    func startScreenshot() {
        startScreenshotTranslation()
    }

    func updateTargetLanguage(_ identifier: String) {
        preferredTargetLanguageIdentifier = identifier
        changeTargetLanguage(identifier)
    }

    func updateTranslationMode(_ mode: TranslationMode) {
        translationMode = mode
        AITranslationPreferences.saveMode(mode)
        if mode == .ai, !aiPrivacyAccepted {
            aiStatusMessage = "启用前请先确认下方云端翻译隐私说明。"
        } else {
            aiStatusMessage = nil
        }
    }

    func updateAIProvider(_ provider: AIProvider) {
        aiProvider = provider
        AITranslationPreferences.saveProvider(provider)
        aiModel = AITranslationPreferences.model(for: provider)
        isKeySaved = (try? credentialStore.read(provider: provider)) != nil
        apiKeyInput = ""
        aiStatusMessage = nil
    }

    func saveAIConfiguration() {
        let trimmedModel = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            aiStatusMessage = "请填写模型名称。"
            return
        }
        if aiProvider == .compatible {
            guard let components = URLComponents(string: compatibleURL),
                  components.scheme?.lowercased() == "https",
                  components.host != nil
            else {
                aiStatusMessage = "兼容服务必须填写完整的 HTTPS 请求地址。"
                return
            }
        }
        AITranslationPreferences.saveModel(trimmedModel, for: aiProvider)
        AITranslationPreferences.saveCompatibleURL(compatibleURL)
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            do {
                try credentialStore.save(key, provider: aiProvider)
                apiKeyInput = ""
                isKeySaved = true
            } catch {
                aiStatusMessage = "API Key 保存失败，请重试。"
                return
            }
        }
        aiStatusMessage = isKeySaved ? "已安全保存到这台 Mac 的系统钥匙串。" : "请填写 API Key。"
    }

    func removeAPIKey() {
        do {
            try credentialStore.delete(provider: aiProvider)
            isKeySaved = false
            apiKeyInput = ""
            aiStatusMessage = "已移除该服务商的 API Key。"
        } catch {
            aiStatusMessage = "API Key 移除失败，请重试。"
        }
    }

    func updatePrivacyAccepted(_ accepted: Bool) {
        aiPrivacyAccepted = accepted
        AITranslationPreferences.savePrivacyAccepted(accepted)
        if !accepted, translationMode == .ai {
            updateTranslationMode(.local)
        } else {
            aiStatusMessage = nil
        }
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            launchAtLogin = launchAtLoginService.isEnabled
            generalStatusMessage = nil
        } catch {
            launchAtLogin = launchAtLoginService.isEnabled
            generalStatusMessage = "无法更改登录时启动设置，请从系统设置中重试。"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var catalog: LanguageCatalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "character.bubble.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("直接开始翻译")
                        .font(.headline)
                    Text("即使没有辅助功能权限，也可以粘贴文字翻译。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("打开翻译器") { model.showTranslator() }
                    .buttonStyle(.borderedProminent)
            }

            Toggle(
                "登录这台 Mac 时自动启动划译",
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.updateLaunchAtLogin($0) }
                )
            )
            if let message = model.generalStatusMessage {
                Text(message).font(.caption).foregroundStyle(.orange)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("默认互译语种")
                    .font(.headline)
                Text("只提供英语、日语、韩语。中文会译成所选语种；所选语种会自动译回中文。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(
                    "互译语种",
                    selection: Binding(
                        get: { model.preferredTargetLanguageIdentifier },
                        set: { model.updateTargetLanguage($0) }
                    )
                ) {
                    ForEach(catalog.options) { option in
                        Text(option.localizedName).tag(option.identifier)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("快捷键")
                    .font(.headline)
                Text("先选中文字，再按第一个快捷键；无法读取选区时会打开中文输入框。截图翻译使用第二个快捷键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("翻译选中文字").frame(width: 112, alignment: .leading)
                    ShortcutRecorderView(
                        shortcut: model.shortcut,
                        onCommit: model.updateShortcut
                    )
                    Button("恢复 ⌘T") { model.restoreDefaultShortcut() }
                        .buttonStyle(.link).font(.caption)
                    Label(
                        model.isSelectionShortcutRegistered ? "可用" : "注册失败",
                        systemImage: model.isSelectionShortcutRegistered
                            ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(model.isSelectionShortcutRegistered ? .green : .orange)
                }
                HStack {
                    Text("截图翻译").frame(width: 112, alignment: .leading)
                    ShortcutRecorderView(
                        shortcut: model.screenshotShortcut,
                        onCommit: model.updateScreenshotShortcut
                    )
                    Button("恢复 ⌥⌘T") { model.restoreDefaultScreenshotShortcut() }
                        .buttonStyle(.link).font(.caption)
                    Label(
                        model.isScreenshotShortcutRegistered ? "可用" : "注册失败",
                        systemImage: model.isScreenshotShortcutRegistered
                            ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(model.isScreenshotShortcutRegistered ? .green : .orange)
                }
                Button {
                    model.startScreenshot()
                } label: {
                    Label("立即试用截图翻译", systemImage: "viewfinder")
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("翻译方式")
                    .font(.headline)
                Picker(
                    "翻译方式",
                    selection: Binding(
                        get: { model.translationMode },
                        set: { model.updateTranslationMode($0) }
                    )
                ) {
                    ForEach(TranslationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if model.translationMode == .local {
                    Label("文字只在这台 Mac 上处理，不需要 API Key。", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("只有你主动翻译的文字会发送给所选服务商。API Key 只保存在这台 Mac 的系统钥匙串。请不要翻译密码、身份证、医疗或公司机密。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Toggle(
                            "我了解云端服务商会处理我主动翻译的文字",
                            isOn: Binding(
                                get: { model.aiPrivacyAccepted },
                                set: { model.updatePrivacyAccepted($0) }
                            )
                        )

                        Picker(
                            "服务商",
                            selection: Binding(
                                get: { model.aiProvider },
                                set: { model.updateAIProvider($0) }
                            )
                        ) {
                            ForEach(AIProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)

                        TextField("模型名称", text: $model.aiModel)
                            .textFieldStyle(.roundedBorder)

                        if model.aiProvider == .compatible {
                            TextField(
                                "完整 HTTPS 请求地址",
                                text: $model.compatibleURL
                            )
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            SecureField(
                                model.isKeySaved ? "已保存；输入新 Key 可覆盖" : "API Key",
                                text: $model.apiKeyInput
                            )
                            .textFieldStyle(.roundedBorder)
                            Button("保存") { model.saveAIConfiguration() }
                                .buttonStyle(.borderedProminent)
                            if model.isKeySaved {
                                Button("移除 Key") { model.removeAPIKey() }
                            }
                        }
                        if let message = model.aiStatusMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Text("权限")
                    .font(.headline)
                HStack(spacing: 9) {
                    Image(systemName: model.hasAccessibilityPermission
                          ? "checkmark.circle.fill"
                          : "exclamationmark.circle.fill")
                        .foregroundStyle(model.hasAccessibilityPermission ? .green : .orange)
                    Text(model.hasAccessibilityPermission ? "已授权" : "需要授权后才能读取和替换选区")
                    Spacer()
                    if !model.hasAccessibilityPermission {
                        Button("打开“辅助功能”设置") { model.requestAccessibilityPermission() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("重新检查") { model.refreshPermission() }
                    }
                }
                Text("系统设置 → 隐私与安全性 → 辅助功能 → 打开“划译”")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 9) {
                    Image(systemName: model.hasScreenCapturePermission
                          ? "checkmark.circle.fill"
                          : "exclamationmark.circle.fill")
                        .foregroundStyle(model.hasScreenCapturePermission ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.hasScreenCapturePermission
                             ? "截图翻译已授权"
                             : "截图翻译需要屏幕录制权限")
                        Text("只读取你主动框选的区域，不会后台录屏")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.hasScreenCapturePermission {
                        Button("打开屏幕录制设置") { model.requestScreenPermission() }
                    } else {
                        Button("重新检查") { model.refreshPermission() }
                    }
                }
            }

            Label("不保存原文或译文历史；AI Key 只存入系统钥匙串。", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 600, height: 720)
        .task { await catalog.loadSupportedLanguages() }
    }
}

import Foundation

enum TranslationMode: String, CaseIterable, Codable, Sendable {
    case local
    case ai

    var displayName: String {
        switch self {
        case .local: "Apple 本机翻译（推荐）"
        case .ai: "AI 高质量翻译（云端）"
        }
    }
}

enum AIProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case deepSeek
    case openAI
    case anthropic
    case gemini
    case compatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .openAI: "OpenAI"
        case .anthropic: "Claude"
        case .gemini: "Gemini"
        case .compatible: "兼容服务"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepSeek: "deepseek-chat"
        case .openAI: "gpt-5-mini"
        case .anthropic: "claude-sonnet-4-5"
        case .gemini: "gemini-2.5-flash"
        case .compatible: ""
        }
    }

    var keychainService: String { "com.local.huayi.ai.\(rawValue)" }
}

struct AITranslationConfiguration: Sendable {
    let provider: AIProvider
    let model: String
    let compatibleURL: String
    let apiKey: String
}

enum AITranslationPreferences {
    static let modeKey = "translationMode"
    static let providerKey = "aiProvider"
    static let compatibleURLKey = "aiCompatibleURL"
    static let privacyAcceptedKey = "aiPrivacyAccepted"

    static func mode(from defaults: UserDefaults = .standard) -> TranslationMode {
        defaults.string(forKey: modeKey).flatMap(TranslationMode.init(rawValue:)) ?? .local
    }

    static func saveMode(_ mode: TranslationMode, to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: modeKey)
    }

    static func provider(from defaults: UserDefaults = .standard) -> AIProvider {
        defaults.string(forKey: providerKey).flatMap(AIProvider.init(rawValue:)) ?? .deepSeek
    }

    static func saveProvider(_ provider: AIProvider, to defaults: UserDefaults = .standard) {
        defaults.set(provider.rawValue, forKey: providerKey)
    }

    static func model(for provider: AIProvider, from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: modelKey(provider)) ?? provider.defaultModel
    }

    static func saveModel(
        _ model: String,
        for provider: AIProvider,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(model, forKey: modelKey(provider))
    }

    static func compatibleURL(from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: compatibleURLKey) ?? ""
    }

    static func saveCompatibleURL(_ value: String, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: compatibleURLKey)
    }

    static func privacyAccepted(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: privacyAcceptedKey)
    }

    static func savePrivacyAccepted(_ value: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: privacyAcceptedKey)
    }

    private static func modelKey(_ provider: AIProvider) -> String {
        "aiModel.\(provider.rawValue)"
    }
}

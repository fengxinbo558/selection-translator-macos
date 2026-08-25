import Foundation

enum AppError: Error, Equatable, Identifiable {
    case accessibilityPermission
    case noSelection
    case protectedContent
    case notEditable
    case selectionChanged
    case sameLanguage
    case languageUnavailable
    case translationFailed
    case translationTimedOut
    case userCancelled
    case clipboardUnavailable
    case screenCapturePermission
    case screenCaptureFailed
    case ocrNoText
    case cloudTranslationFailed(String)

    var id: String { userMessage }

    var userMessage: String {
        switch self {
        case .accessibilityPermission:
            "需要开启辅助功能权限，才能读取并替换选中的文字。"
        case .noSelection:
            "请先选中要翻译的文字。"
        case .protectedContent:
            "出于安全原因，不能读取密码或受保护的文字。"
        case .notEditable:
            "这里不能直接替换，译文已准备好供你复制。"
        case .selectionChanged:
            "原来的选区已发生变化，没有替换文字。"
        case .sameLanguage:
            "选中的文字已经是该语言。"
        case .languageUnavailable:
            "这组语言暂时无法翻译。"
        case .translationFailed:
            "翻译没有完成，请重试。"
        case .translationTimedOut:
            "翻译等待时间过长，已停止。请重试。"
        case .userCancelled:
            "已取消翻译。"
        case .clipboardUnavailable:
            "无法访问剪贴板，请重试。"
        case .screenCapturePermission:
            "截图翻译需要开启“屏幕与系统音频录制”权限。"
        case .screenCaptureFailed:
            "没有截取到这个区域，请重新框选。"
        case .ocrNoText:
            "这个区域没有识别到文字，请框选更清晰、更小的区域。"
        case .cloudTranslationFailed(let message):
            message
        }
    }
}

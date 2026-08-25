enum SelectionFallbackPolicy {
    static func shouldOpenManualInput(after error: AppError) -> Bool {
        error == .accessibilityPermission || error == .noSelection
    }
}

import SwiftUI
import Translation

struct CompactTranslationView: View {
    @ObservedObject var model: CompactTranslationModel
    @StateObject private var speech = SpeechPlaybackController()

    var body: some View {
        let requestID = model.currentRequestID
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "character.bubble.fill")
                    .foregroundStyle(.tint)
                Text("与中文互译")
                    .font(.system(size: 13, weight: .semibold))
                Picker(
                    "目标语言",
                    selection: Binding(
                        get: { model.selectedTarget?.identifier ?? "" },
                        set: { model.selectTarget(identifier: $0) }
                    )
                ) {
                    ForEach(model.catalog.options) { option in
                        Text(option.localizedName).tag(option.identifier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("目标语言")

                Button(action: model.close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }

            Divider()
            Text(model.directionText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(width: 360, height: 208, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
        .translationTask(model.configuration) { session in
            await model.performTranslation(using: session, requestID: requestID)
        }
        .onChange(of: model.translatedText) { _, _ in speech.stop() }
        .onDisappear { speech.stop() }
        .onExitCommand(perform: model.close)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .translating:
            statusRow(icon: "arrow.triangle.2.circlepath", title: "正在翻译…") {
                ProgressView().controlSize(.small)
            }
        case .preparingLanguage:
            statusRow(icon: "arrow.down.circle", title: "正在准备语言…") {
                ProgressView().controlSize(.small)
            }
        case .replaced:
            VStack(alignment: .leading, spacing: 7) {
                Label("已直接替换选中文字", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13.5, weight: .semibold))
                if let translatedText = model.translatedText {
                    Text(translatedText)
                        .font(.caption)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                resultActionButtons(includeCopy: false)
            }
        case .resultReady:
            VStack(alignment: .leading, spacing: 9) {
                Text(model.translatedText ?? "")
                    .font(.system(size: 13.5))
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text("原位置只读，译文显示在这里")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    resultActionButtons(includeCopy: true)
                }
            }
        case .error(let error):
            VStack(alignment: .leading, spacing: 7) {
                Label(error.userMessage, systemImage: "exclamationmark.circle")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if let explanation = model.abbreviationExplanation {
                    AbbreviationExplanationButton(explanation: explanation)
                }
                Text(error == .noSelection
                     ? "选中文字后按 ⌘T，会自动翻译并直接替换。"
                     : "可以从上方下拉框换一种语言后重试。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusRow<Accessory: View>(
        icon: String,
        title: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
            Spacer()
            accessory()
        }
    }

    private func resultActionButtons(includeCopy: Bool) -> some View {
        HStack(spacing: 6) {
            if let explanation = model.abbreviationExplanation {
                AbbreviationExplanationButton(explanation: explanation)
            }
            TranslationSpeechButton(
                speech: speech,
                itemID: "translation",
                title: "朗读译文",
                text: model.translatedText ?? "",
                languageIdentifier: model.speechLanguageIdentifier
            )
            if includeCopy {
                Button(model.didCopy ? "已复制" : "复制") {
                    model.copyTranslation()
                }
                .controlSize(.small)
                .disabled(model.didCopy)
            }
        }
    }
}

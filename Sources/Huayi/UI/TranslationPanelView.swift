import SwiftUI
import Translation

struct TranslationPanelView: View {
    @ObservedObject var model: TranslationPanelModel
    @FocusState private var sourceFocused: Bool
    @State private var debounceTask: Task<Void, Never>?
    @StateObject private var speech = SpeechPlaybackController()

    var body: some View {
        let requestID = model.currentRequestID
        VStack(spacing: 0) {
            header
            Divider()
            sourceEditor
            Divider()
            resultArea
        }
        .frame(width: 460, height: 470)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 28, y: 12)
        .task {
            await model.catalog.loadSupportedLanguages()
            model.activateDefaultTarget()
            sourceFocused = model.sourceText.isEmpty
        }
        .onChange(of: model.sourceText) { _, _ in
            speech.stop()
            guard model.isManualEntry else { return }
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(360))
                guard !Task.isCancelled else { return }
                model.restartForCurrentTarget()
            }
        }
        .background {
            TranslationPanelTaskHost(model: model, requestID: requestID)
                .id(requestID)
        }
        .onChange(of: model.translatedText) { _, _ in speech.stop() }
        .onDisappear { speech.stop() }
        .onExitCommand { model.cancel() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "character.bubble.fill")
                .foregroundStyle(.tint)
            Text("划译")
                .font(.headline)
            Spacer()
            if let onCaptureScreenshot = model.onCaptureScreenshot {
                Button(action: onCaptureScreenshot) {
                    Label(
                        "截图翻译 \(model.screenshotShortcutDisplayString)",
                        systemImage: "viewfinder"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("框选屏幕文字并自动翻译")
            }
            SpeechRatePicker(speech: speech)
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
            .frame(width: 112)
            .accessibilityLabel("目标语言")
            if let onOpenSettings = model.onOpenSettings {
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("设置")
            }
            Button(action: model.cancel) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("输入中文", systemImage: "text.cursor")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("也可输入英语、日语或韩语")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                TranslationSpeechButton(
                    speech: speech,
                    itemID: "source",
                    title: "朗读原文",
                    text: model.sourceText,
                    languageIdentifier: model.sourceSpeechLanguageIdentifier
                )
                if !model.sourceText.isEmpty {
                    Button("清空") { model.sourceText = "" }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ZStack(alignment: .topLeading) {
                if model.sourceText.isEmpty {
                    Text("在这里输入或粘贴中文，会自动翻译…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 7)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.sourceText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .focused($sourceFocused)
                    .accessibilityLabel("输入中文，也可以输入英语、日语或韩语")
            }
            .padding(4)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .frame(height: 170)
    }

    @ViewBuilder
    private var resultArea: some View {
        switch model.state {
        case .idle:
            emptyResult
        case .preparingLanguage:
            progress(title: "正在准备语言…", detail: "首次使用可能需要下载语言包")
        case .translating:
            progress(title: "正在翻译…", detail: model.selectedTarget?.localizedName ?? "")
        case .resultReady:
            result
        case .success:
            progress(title: "已替换", detail: "可在原应用中按 ⌘Z 撤销")
        case .error(let error):
            errorView(error)
        }
    }

    private var emptyResult: some View {
        VStack(spacing: 9) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("译文会显示在这里")
                .font(.headline)
            Text(model.directionText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progress(title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(model.directionText, systemImage: "checkmark.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
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
                Button(model.didCopy ? "已复制" : "复制译文") { model.copyTranslation() }
                    .disabled(model.didCopy)
            }
            ScrollView {
                Text(model.translatedText ?? "")
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(11)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: AppError) -> some View {
        VStack(spacing: 11) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.orange)
            Text(error.userMessage)
                .multilineTextAlignment(.center)
            if let explanation = model.abbreviationExplanation {
                AbbreviationExplanationButton(explanation: explanation)
            }
            if !model.sourceText.isEmpty {
                Button("重试") { model.retry() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TranslationPanelTaskHost: View {
    @ObservedObject var model: TranslationPanelModel
    let requestID: Int

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(model.configuration) { session in
                await model.performTranslation(using: session, requestID: requestID)
            }
    }
}

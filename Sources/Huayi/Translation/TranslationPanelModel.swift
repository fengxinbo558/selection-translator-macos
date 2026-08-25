import Combine
import Foundation
@preconcurrency import Translation

enum TranslationPanelState: Equatable {
    case idle
    case preparingLanguage
    case translating
    case resultReady
    case success
    case error(AppError)

    var isBusy: Bool {
        self == .preparingLanguage || self == .translating
    }
}

@MainActor
final class TranslationPanelModel: ObservableObject {
    typealias ReplaceAction = @MainActor (
        _ translatedText: String,
        _ snapshot: SelectionSnapshot
    ) async throws -> Void
    typealias CopyAction = @MainActor (_ text: String) throws -> Void
    typealias LanguageDetector = @MainActor (_ text: String) -> Locale.Language?
    typealias AvailabilityChecker = @MainActor (
        _ source: Locale.Language,
        _ target: Locale.Language
    ) async -> LanguageAvailability.Status
    typealias PreparationAction = @MainActor () async throws -> Void
    typealias TranslationAction = @MainActor (_ text: String) async throws -> String
    typealias CloudTranslation = @MainActor (
        _ text: String,
        _ target: LanguageOption
    ) async throws -> AsyncThrowingStream<String, Error>

    @Published var query = ""
    @Published var highlightedIndex = 0
    @Published var sourceText: String
    @Published private(set) var state: TranslationPanelState = .idle
    @Published private(set) var selectedTarget: LanguageOption?
    @Published private(set) var directionText = "中文 → 英语"
    @Published private(set) var translatedText: String?
    @Published private(set) var didCopy = false
    @Published var configuration: TranslationSession.Configuration?
    private(set) var currentRequestID = 0

    let snapshot: SelectionSnapshot
    let catalog: LanguageCatalog
    let isManualEntry: Bool
    let initialTargetIdentifier: String?
    let screenshotShortcutDisplayString: String
    var onSuccess: (() -> Void)?
    var onCancel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCaptureScreenshot: (() -> Void)?
    var onTargetChanged: ((String) -> Void)?

    private let replaceAction: ReplaceAction
    private let copyAction: CopyAction
    private let languageDetector: LanguageDetector
    private let availabilityChecker: AvailabilityChecker
    private let cloudTranslation: CloudTranslation?
    private let localTranslationTimeout: Duration
    private let languagePreparationTimeout: Duration
    private let cloudTranslationTimeout: Duration
    private var cloudTask: Task<Void, Never>?
    private var localConfigurationTask: Task<Void, Never>?
    private var localStartupTimeoutTask: Task<Void, Never>?
    private var actualTarget: LanguageOption?

    init(
        snapshot: SelectionSnapshot,
        catalog: LanguageCatalog,
        replaceAction: @escaping ReplaceAction,
        copyAction: @escaping CopyAction,
        isManualEntry: Bool = false,
        initialTargetIdentifier: String? = nil,
        screenshotShortcutDisplayString: String = "⌥⌘T",
        cloudTranslation: CloudTranslation? = nil,
        localTranslationTimeout: Duration = .seconds(20),
        languagePreparationTimeout: Duration = .seconds(120),
        cloudTranslationTimeout: Duration = .seconds(30),
        languageDetector: @escaping LanguageDetector = {
            SourceLanguageResolver.resolve(text: $0)
        },
        availabilityChecker: @escaping AvailabilityChecker = { source, target in
            await LanguageAvailability().status(from: source, to: target)
        }
    ) {
        self.snapshot = snapshot
        self.catalog = catalog
        self.replaceAction = replaceAction
        self.copyAction = copyAction
        self.isManualEntry = isManualEntry
        self.initialTargetIdentifier = initialTargetIdentifier
        self.screenshotShortcutDisplayString = screenshotShortcutDisplayString
        sourceText = snapshot.originalText
        self.languageDetector = languageDetector
        self.availabilityChecker = availabilityChecker
        self.cloudTranslation = cloudTranslation
        self.localTranslationTimeout = localTranslationTimeout
        self.languagePreparationTimeout = languagePreparationTimeout
        self.cloudTranslationTimeout = cloudTranslationTimeout
    }

    var canReplace: Bool {
        !isManualEntry && snapshot.replacementCapability != .copyOnly
    }

    var abbreviationExplanation: AbbreviationExplanation? {
        AbbreviationGlossary.explanation(for: sourceText)
    }

    var speechLanguageIdentifier: String? {
        actualTarget?.identifier
    }

    var sourceSpeechLanguageIdentifier: String? {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return resolvedSourceLanguage(for: text)?.minimalIdentifier
    }

    var visibleOptions: [LanguageOption] {
        catalog.filteredOptions(query: query)
    }

    var recentOptions: [LanguageOption] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return catalog.recentOptions
    }

    func beginTranslation(to target: LanguageOption) {
        guard !state.isBusy else { return }
        currentRequestID &+= 1

        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            clearLocalTranslationConfiguration()
            state = .error(.noSelection)
            return
        }

        let source = resolvedSourceLanguage(for: text)
        let direction = BidirectionalTargetResolver.resolve(source: source, partner: target)

        selectedTarget = target
        actualTarget = direction.actualTarget
        directionText = direction.label
        translatedText = nil
        didCopy = false
        state = .translating
        if cloudTranslation != nil {
            clearLocalTranslationConfiguration()
            startCloudTranslation(target: direction.actualTarget, requestID: currentRequestID)
            return
        }
        configureLocalTranslation(
            source: source,
            target: direction.actualTarget.language,
            requestID: currentRequestID
        )
    }

    func activateDefaultTarget() {
        guard selectedTarget == nil else { return }
        let target = catalog.options.first {
            $0.identifier.caseInsensitiveCompare(initialTargetIdentifier ?? "en") == .orderedSame
        } ?? catalog.options.first {
            $0.identifier.caseInsensitiveCompare("en") == .orderedSame
        } ?? catalog.options.first
        guard let target else { return }
        restartTranslation(to: target)
    }

    func selectTarget(identifier: String) {
        guard let target = catalog.options.first(where: {
            $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame
        }) else { return }
        onTargetChanged?(target.identifier)
        restartTranslation(to: target)
    }

    func restartForCurrentTarget() {
        guard let selectedTarget else { return }
        restartTranslation(to: selectedTarget)
    }

    func restartTranslation(to target: LanguageOption) {
        currentRequestID &+= 1
        selectedTarget = target
        translatedText = nil
        didCopy = false

        let defaultDirection = BidirectionalTargetResolver.resolve(source: nil, partner: target)
        actualTarget = defaultDirection.actualTarget
        directionText = defaultDirection.label

        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            clearLocalTranslationConfiguration()
            state = .idle
            return
        }
        let source = resolvedSourceLanguage(for: text)
        let direction = BidirectionalTargetResolver.resolve(source: source, partner: target)
        actualTarget = direction.actualTarget
        directionText = direction.label
        state = .translating
        cloudTask?.cancel()
        if cloudTranslation != nil {
            clearLocalTranslationConfiguration()
            startCloudTranslation(target: direction.actualTarget, requestID: currentRequestID)
            return
        }
        configureLocalTranslation(
            source: source,
            target: direction.actualTarget.language,
            requestID: currentRequestID
        )
    }

    func performTranslation(using session: TranslationSession, requestID: Int) async {
        await performTranslation(
            requestID: requestID,
            sourceLanguage: session.sourceLanguage,
            targetLanguage: session.targetLanguage,
            prepare: { try await session.prepareTranslation() },
            translate: { try await session.translate($0).targetText }
        )
    }

    func performTranslation(
        requestID: Int,
        sourceLanguage: Locale.Language?,
        targetLanguage: Locale.Language?,
        prepare: @escaping PreparationAction,
        translate: @escaping TranslationAction
    ) async {
        guard requestID == currentRequestID, state.isBusy else { return }
        localStartupTimeoutTask?.cancel()
        localStartupTimeoutTask = nil
        guard let actualTarget else { return }
        let target = targetLanguage ?? actualTarget.language
        guard languagesMatch(target, actualTarget.language) else { return }
        let text = translationInputText
        var timeoutTask = translationTimeoutTask(
            requestID: requestID,
            after: localTranslationTimeout
        )
        defer { timeoutTask.cancel() }

        do {
            if let sourceLanguage {
                let availability = await availabilityChecker(sourceLanguage, target)
                guard requestID == currentRequestID else { return }
                switch availability {
                case .installed:
                    break
                case .supported:
                    state = .preparingLanguage
                    timeoutTask.cancel()
                    timeoutTask = translationTimeoutTask(
                        requestID: requestID,
                        after: languagePreparationTimeout
                    )
                    try await prepare()
                    guard requestID == currentRequestID else { return }
                case .unsupported:
                    state = .error(.languageUnavailable)
                    return
                @unknown default:
                    state = .error(.languageUnavailable)
                    return
                }
            }

            state = .translating
            timeoutTask.cancel()
            timeoutTask = translationTimeoutTask(
                requestID: requestID,
                after: localTranslationTimeout
            )
            let targetText = try await translate(text)
            guard requestID == currentRequestID else { return }
            await completeTranslation(targetText)
        } catch is CancellationError {
            handleCancellation(requestID: requestID)
        } catch {
            if (error as NSError).code == NSUserCancelledError {
                handleCancellation(requestID: requestID)
                return
            }
            guard requestID == currentRequestID else { return }
            state = .error(mapTranslationError(error))
        }
    }

    func completeTranslation(_ text: String) async {
        localStartupTimeoutTask?.cancel()
        localStartupTimeoutTask = nil
        translatedText = text
        if let selectedTarget { catalog.recordUse(selectedTarget) }
        state = .resultReady
    }

    func replaceTranslation() async {
        guard state == .resultReady, canReplace, let translatedText else { return }
        do {
            try await replaceAction(translatedText, snapshot)
            state = .success
            onSuccess?()
        } catch let error as AppError {
            state = .error(error)
        } catch {
            state = .error(.translationFailed)
        }
    }

    func copyTranslation() {
        guard let translatedText else { return }
        do {
            try copyAction(translatedText)
            didCopy = true
        } catch {
            state = .error(.clipboardUnavailable)
        }
    }

    func retry() {
        guard let selectedTarget else { return }
        state = .idle
        beginTranslation(to: selectedTarget)
    }

    func returnToLanguageList() {
        currentRequestID &+= 1
        cloudTask?.cancel()
        clearLocalTranslationConfiguration()
        translatedText = nil
        didCopy = false
        state = .idle
    }

    func cancel() {
        currentRequestID &+= 1
        cloudTask?.cancel()
        clearLocalTranslationConfiguration()
        onCancel?()
    }

    private func handleCancellation(requestID: Int) {
        guard requestID == currentRequestID else { return }
        currentRequestID &+= 1
        clearLocalTranslationConfiguration()
        selectedTarget = nil
        actualTarget = nil
        translatedText = nil
        didCopy = false
        state = .idle
    }

    private func startCloudTranslation(target: LanguageOption, requestID: Int) {
        guard let cloudTranslation else { return }
        let source = translationInputText
        cloudTask = Task { [weak self] in
            guard let self else { return }
            let timeoutTask = translationTimeoutTask(
                requestID: requestID,
                after: cloudTranslationTimeout,
                cancelCloudTask: true
            )
            defer { timeoutTask.cancel() }
            do {
                let stream = try await cloudTranslation(source, target)
                var output = ""
                for try await delta in stream {
                    guard !Task.isCancelled, requestID == currentRequestID else { return }
                    output += delta
                    translatedText = output
                    state = .resultReady
                }
                guard !Task.isCancelled, requestID == currentRequestID else { return }
                guard !output.isEmpty else { throw AITranslationError.invalidResponse }
                if let selectedTarget { catalog.recordUse(selectedTarget) }
                translatedText = output
                state = .resultReady
            } catch is CancellationError {
                guard requestID == currentRequestID else { return }
                state = .idle
            } catch {
                guard requestID == currentRequestID else { return }
                state = .error(.cloudTranslationFailed(
                    (error as? LocalizedError)?.errorDescription ?? "AI 翻译没有完成，请重试。"
                ))
            }
        }
    }

    private func translationTimeoutTask(
        requestID: Int,
        after duration: Duration,
        cancelCloudTask: Bool = false
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard let self, requestID == currentRequestID, state.isBusy else { return }
            currentRequestID &+= 1
            clearLocalTranslationConfiguration()
            state = .error(.translationTimedOut)
            if cancelCloudTask {
                cloudTask?.cancel()
            }
        }
    }

    private func languagesMatch(_ source: Locale.Language, _ target: Locale.Language) -> Bool {
        source.minimalIdentifier.caseInsensitiveCompare(target.minimalIdentifier) == .orderedSame
    }

    private var translationInputText: String {
        abbreviationExplanation?.fullName ?? sourceText
    }

    private func resolvedSourceLanguage(for text: String) -> Locale.Language? {
        if AbbreviationGlossary.explanation(for: text) != nil
            || SourceLanguageResolver.isLikelyEnglishTechnicalToken(text) {
            return Locale.Language(identifier: "en")
        }
        return languageDetector(text)
    }

    private func configureLocalTranslation(
        source: Locale.Language?,
        target: Locale.Language,
        requestID: Int
    ) {
        let needsSeparateViewUpdate = configuration != nil || localConfigurationTask != nil
        clearLocalTranslationConfiguration()

        guard needsSeparateViewUpdate else {
            configuration = .init(source: source, target: target)
            armLocalStartupTimeout(requestID: requestID)
            return
        }

        localConfigurationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled,
                  let self,
                  requestID == currentRequestID,
                  state.isBusy,
                  cloudTranslation == nil
            else { return }
            configuration = .init(source: source, target: target)
            localConfigurationTask = nil
            armLocalStartupTimeout(requestID: requestID)
        }
    }

    private func clearLocalTranslationConfiguration() {
        localConfigurationTask?.cancel()
        localConfigurationTask = nil
        localStartupTimeoutTask?.cancel()
        localStartupTimeoutTask = nil
        configuration?.invalidate()
        configuration = nil
    }

    private func armLocalStartupTimeout(requestID: Int) {
        localStartupTimeoutTask?.cancel()
        localStartupTimeoutTask = translationTimeoutTask(
            requestID: requestID,
            after: localTranslationTimeout
        )
    }

    private func mapTranslationError(_ error: Error) -> AppError {
        if TranslationError.unsupportedSourceLanguage ~= error
            || TranslationError.unsupportedTargetLanguage ~= error
            || TranslationError.unsupportedLanguagePairing ~= error {
            return .languageUnavailable
        }
        if TranslationError.unableToIdentifyLanguage ~= error
            || TranslationError.nothingToTranslate ~= error {
            return .noSelection
        }
        return .translationFailed
    }
}

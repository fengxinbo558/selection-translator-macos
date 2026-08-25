import Combine
import Foundation
@preconcurrency import Translation

enum CompactTranslationState: Equatable {
    case idle
    case preparingLanguage
    case translating
    case replaced
    case resultReady
    case error(AppError)

    var isBusy: Bool {
        self == .preparingLanguage || self == .translating
    }
}

@MainActor
final class CompactTranslationModel: ObservableObject {
    typealias ReplaceAction = @MainActor (_ translatedText: String) async throws -> Void
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

    @Published private(set) var state: CompactTranslationState = .idle
    @Published private(set) var selectedTarget: LanguageOption?
    @Published private(set) var directionText = "中文 → 英语"
    @Published private(set) var translatedText: String?
    @Published private(set) var didCopy = false
    @Published var configuration: TranslationSession.Configuration?
    @Published private(set) var currentRequestID = 0

    let originalText: String
    let catalog: LanguageCatalog
    let canReplace: Bool
    var onClose: (() -> Void)?
    var onTargetChanged: ((String) -> Void)?

    private let replaceAction: ReplaceAction
    private let copyAction: CopyAction
    private let languageDetector: LanguageDetector
    private let availabilityChecker: AvailabilityChecker
    private var autoCloseTask: Task<Void, Never>?
    private let cloudTranslation: CloudTranslation?
    private let localTranslationTimeout: Duration
    private let languagePreparationTimeout: Duration
    private let cloudTranslationTimeout: Duration
    private var cloudTask: Task<Void, Never>?
    private var actualTarget: LanguageOption?

    init(
        snapshot: SelectionSnapshot,
        catalog: LanguageCatalog,
        replaceAction: @escaping ReplaceAction,
        copyAction: @escaping CopyAction,
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
        originalText = snapshot.originalText
        self.catalog = catalog
        canReplace = snapshot.replacementCapability != .copyOnly
        self.replaceAction = replaceAction
        self.copyAction = copyAction
        self.languageDetector = languageDetector
        self.availabilityChecker = availabilityChecker
        self.cloudTranslation = cloudTranslation
        self.localTranslationTimeout = localTranslationTimeout
        self.languagePreparationTimeout = languagePreparationTimeout
        self.cloudTranslationTimeout = cloudTranslationTimeout
    }

    var abbreviationExplanation: AbbreviationExplanation? {
        AbbreviationGlossary.explanation(for: originalText)
    }

    var speechLanguageIdentifier: String? {
        actualTarget?.identifier
    }

    func start(to target: LanguageOption, rememberChoice: Bool = false) {
        autoCloseTask?.cancel()
        currentRequestID &+= 1
        selectedTarget = target
        let defaultDirection = BidirectionalTargetResolver.resolve(source: nil, partner: target)
        actualTarget = defaultDirection.actualTarget
        directionText = defaultDirection.label

        let text = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            configuration?.invalidate()
            configuration = nil
            state = .error(.noSelection)
            return
        }

        let source = resolvedSourceLanguage(for: text)
        let direction = BidirectionalTargetResolver.resolve(source: source, partner: target)
        actualTarget = direction.actualTarget
        directionText = direction.label

        translatedText = nil
        didCopy = false
        state = .translating
        if rememberChoice { onTargetChanged?(target.identifier) }
        cloudTask?.cancel()
        if cloudTranslation != nil {
            configuration?.invalidate()
            configuration = nil
            startCloudTranslation(target: direction.actualTarget, requestID: currentRequestID)
            return
        }
        if let configuration,
           languagesMatch(
               configuration.target ?? direction.actualTarget.language,
               direction.actualTarget.language
           ),
           optionalLanguagesMatch(configuration.source, source) {
            self.configuration?.invalidate()
        } else {
            configuration = .init(source: source, target: direction.actualTarget.language)
        }
    }

    func selectTarget(identifier: String) {
        guard let target = catalog.options.first(where: {
            $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame
        }) else { return }
        start(to: target, rememberChoice: true)
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
        guard requestID == currentRequestID, state.isBusy, let actualTarget else { return }
        let target = targetLanguage ?? actualTarget.language
        guard languagesMatch(target, actualTarget.language) else { return }
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
            let targetText = try await translate(translationInputText)
            guard requestID == currentRequestID else { return }
            try await completeTranslation(targetText, requestID: requestID)
        } catch is CancellationError {
            guard requestID == currentRequestID else { return }
            state = .idle
        } catch let error as AppError {
            guard requestID == currentRequestID else { return }
            state = .error(error)
        } catch {
            if (error as NSError).code == NSUserCancelledError {
                guard requestID == currentRequestID else { return }
                state = .idle
                return
            }
            guard requestID == currentRequestID else { return }
            state = .error(mapTranslationError(error))
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

    func close() {
        autoCloseTask?.cancel()
        cloudTask?.cancel()
        currentRequestID &+= 1
        configuration?.invalidate()
        configuration = nil
        onClose?()
    }

    private func completeTranslation(_ text: String, requestID: Int) async throws {
        translatedText = text
        catalog.recordUse(selectedTarget!)
        if canReplace {
            try await replaceAction(text)
            guard requestID == currentRequestID else { return }
            state = .replaced
            if abbreviationExplanation == nil {
                scheduleAutoClose(for: requestID)
            }
        } else {
            state = .resultReady
        }
    }

    private func scheduleAutoClose(for requestID: Int) {
        autoCloseTask?.cancel()
        autoCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled,
                  let self,
                  requestID == currentRequestID,
                  state == .replaced
            else { return }
            close()
        }
    }

    private func startCloudTranslation(target: LanguageOption, requestID: Int) {
        guard let cloudTranslation else { return }
        cloudTask = Task { [weak self] in
            guard let self else { return }
            let timeoutTask = translationTimeoutTask(
                requestID: requestID,
                after: cloudTranslationTimeout,
                cancelCloudTask: true
            )
            defer { timeoutTask.cancel() }
            do {
                let stream = try await cloudTranslation(translationInputText, target)
                var output = ""
                for try await delta in stream {
                    guard !Task.isCancelled, requestID == currentRequestID else { return }
                    output += delta
                    if !canReplace {
                        translatedText = output
                        state = .resultReady
                    }
                }
                guard !Task.isCancelled, requestID == currentRequestID else { return }
                guard !output.isEmpty else { throw AITranslationError.invalidResponse }
                try await completeTranslation(output, requestID: requestID)
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
            configuration?.invalidate()
            configuration = nil
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
        abbreviationExplanation?.fullName ?? originalText
    }

    private func resolvedSourceLanguage(for text: String) -> Locale.Language? {
        if AbbreviationGlossary.explanation(for: text) != nil
            || SourceLanguageResolver.isLikelyEnglishTechnicalToken(text) {
            return Locale.Language(identifier: "en")
        }
        return languageDetector(text)
    }

    private func optionalLanguagesMatch(
        _ lhs: Locale.Language?,
        _ rhs: Locale.Language?
    ) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            true
        case let (.some(lhs), .some(rhs)):
            languagesMatch(lhs, rhs)
        default:
            false
        }
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

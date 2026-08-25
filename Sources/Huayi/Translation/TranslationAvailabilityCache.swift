import Foundation
@preconcurrency import Translation

@MainActor
final class TranslationAvailabilityCache {
    typealias Loader = @MainActor (
        _ source: Locale.Language,
        _ target: Locale.Language
    ) async -> LanguageAvailability.Status

    private struct Pair: Hashable {
        let source: String
        let target: String
    }

    private let loader: Loader
    private var stableStatuses: [Pair: LanguageAvailability.Status] = [:]

    init(loader: @escaping Loader = { source, target in
        await LanguageAvailability().status(from: source, to: target)
    }) {
        self.loader = loader
    }

    func status(
        from source: Locale.Language,
        to target: Locale.Language
    ) async -> LanguageAvailability.Status {
        let pair = Pair(
            source: source.minimalIdentifier,
            target: target.minimalIdentifier
        )
        if let cached = stableStatuses[pair] { return cached }

        let status = await loader(source, target)
        if status == .installed || status == .unsupported {
            stableStatuses[pair] = status
        }
        return status
    }
}

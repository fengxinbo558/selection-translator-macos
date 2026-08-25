import Foundation

enum SpeechRate: Double, CaseIterable, Identifiable, Sendable {
    case normal = 1
    case oneAndQuarter = 1.25
    case oneAndHalf = 1.5
    case double = 2
    case triple = 3
    case quadruple = 4
    case quintuple = 5

    var id: Double { rawValue }

    var displayName: String {
        switch self {
        case .normal: "1×"
        case .oneAndQuarter: "1.25×"
        case .oneAndHalf: "1.5×"
        case .double: "2×"
        case .triple: "3×"
        case .quadruple: "4×"
        case .quintuple: "5×"
        }
    }
}

enum SpeechPreferences {
    static let rateKey = "speechRate"

    static func rate(from defaults: UserDefaults = .standard) -> SpeechRate {
        let stored = defaults.double(forKey: rateKey)
        return SpeechRate(rawValue: stored) ?? .normal
    }

    static func saveRate(_ rate: SpeechRate, to defaults: UserDefaults = .standard) {
        defaults.set(rate.rawValue, forKey: rateKey)
    }
}

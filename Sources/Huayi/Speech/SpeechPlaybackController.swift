@preconcurrency import AVFoundation
import Combine
import Foundation

enum SpeechLanguageResolver {
    static func voiceLanguage(for identifier: String?) -> String {
        let normalized = (identifier ?? "").lowercased()
        if normalized.hasPrefix("ja") { return "ja-JP" }
        if normalized.hasPrefix("ko") { return "ko-KR" }
        if normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh-tw") {
            return "zh-TW"
        }
        if normalized.hasPrefix("zh") { return "zh-CN" }
        if normalized.hasPrefix("en") { return "en-US" }
        guard let identifier, !identifier.isEmpty else { return "en-US" }
        return identifier
    }
}

enum SpeechVoiceResolver {
    private static let preferredIdentifiers: [String: [String]] = [
        "en-US": [
            "com.apple.ttsbundle.siri_nicky_en-US_compact",
            "com.apple.ttsbundle.siri_aaron_en-US_compact",
            "com.apple.voice.compact.en-US.Samantha"
        ],
        "zh-CN": [
            "com.apple.ttsbundle.siri_yushu_zh-CN_compact",
            "com.apple.ttsbundle.siri_limu_zh-CN_compact",
            "com.apple.voice.compact.zh-CN.Tingting"
        ],
        "zh-TW": ["com.apple.voice.compact.zh-TW.Meijia"],
        "ja-JP": [
            "com.apple.ttsbundle.siri_oren_ja-JP_compact",
            "com.apple.ttsbundle.siri_hattori_ja-JP_compact",
            "com.apple.voice.compact.ja-JP.Kyoko"
        ],
        "ko-KR": ["com.apple.voice.compact.ko-KR.Yuna"]
    ]

    static func voice(for languageIdentifier: String?) -> AVSpeechSynthesisVoice? {
        let language = SpeechLanguageResolver.voiceLanguage(for: languageIdentifier)
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.caseInsensitiveCompare(language) == .orderedSame
        }
        return candidates.max {
            voiceRank($0, language: language) < voiceRank($1, language: language)
        }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    private static func voiceRank(_ voice: AVSpeechSynthesisVoice, language: String) -> Int {
        rankingScore(
            qualityRawValue: voice.quality.rawValue,
            name: voice.name,
            identifier: voice.identifier,
            language: language
        )
    }

    static func rankingScore(
        qualityRawValue: Int,
        name: String,
        identifier: String,
        language: String
    ) -> Int {
        var rank = qualityRawValue * 1_000
        let normalizedIdentifier = identifier.lowercased()
        if let index = preferredIdentifiers[language, default: []]
            .firstIndex(of: identifier) {
            rank += 200 - index * 10
        }
        if language == "en-US", name.lowercased() == "ava" {
            rank += 250
        }
        if language == "en-US", name.lowercased() == "samantha" {
            rank += 20
        }
        if language.hasPrefix("zh"), name.lowercased().contains("tingting") {
            rank += 20
        }
        if normalizedIdentifier.contains(".siri_") { rank += 60 }
        if normalizedIdentifier.contains(".eloquence.") { rank -= 100 }
        if normalizedIdentifier.contains(".speech.synthesis.") { rank -= 200 }
        return rank
    }
}

private enum SpeechRenderResult: Sendable {
    case success(URL)
    case failure
}

private final class SpeechBufferWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var audioFile: AVAudioFile?
    private var wroteAudio = false
    private var finished = false

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("huayi-speech-\(UUID().uuidString)")
            .appendingPathExtension("caf")
    }

    func consume(_ buffer: AVAudioBuffer) -> SpeechRenderResult? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return nil }
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
            finished = true
            audioFile = nil
            return .failure
        }

        if pcmBuffer.frameLength == 0 {
            finished = true
            audioFile = nil
            return wroteAudio ? .success(url) : .failure
        }

        do {
            if audioFile == nil {
                audioFile = try AVAudioFile(
                    forWriting: url,
                    settings: pcmBuffer.format.settings,
                    commonFormat: pcmBuffer.format.commonFormat,
                    interleaved: pcmBuffer.format.isInterleaved
                )
            }
            try audioFile?.write(from: pcmBuffer)
            wroteAudio = true
            return nil
        } catch {
            finished = true
            audioFile = nil
            return .failure
        }
    }
}

@MainActor
final class SpeechPlaybackController: ObservableObject {
    @Published private(set) var activeItemID: String?
    @Published private(set) var rate: SpeechRate

    private let synthesizer: AVSpeechSynthesizer
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var activeAudioFile: AVAudioFile?
    private var activeTemporaryURL: URL?
    private var generation = 0

    var isSpeaking: Bool {
        activeItemID != nil
    }

    init() {
        synthesizer = AVSpeechSynthesizer()
        rate = SpeechPreferences.rate()
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitch)
        audioEngine.connect(playerNode, to: timePitch, format: nil)
        audioEngine.connect(timePitch, to: audioEngine.mainMixerNode, format: nil)
        timePitch.rate = Float(rate.rawValue)
    }

    func isSpeaking(itemID: String) -> Bool {
        activeItemID == itemID
    }

    func toggle(itemID: String, text: String, languageIdentifier: String?) {
        if isSpeaking(itemID: itemID) {
            stop()
            return
        }
        speak(itemID: itemID, text: text, languageIdentifier: languageIdentifier)
    }

    func setRate(_ rate: SpeechRate) {
        self.rate = rate
        SpeechPreferences.saveRate(rate)
        timePitch.rate = Float(rate.rawValue)
    }

    func speak(itemID: String, text: String, languageIdentifier: String?) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        stop()
        generation &+= 1
        let requestGeneration = generation
        let utterance = AVSpeechUtterance(string: content)
        utterance.voice = SpeechVoiceResolver.voice(for: languageIdentifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 1
        activeItemID = itemID

        let writer = SpeechBufferWriter()
        synthesizer.write(utterance) { [weak self] buffer in
            guard let result = writer.consume(buffer) else { return }
            Task { @MainActor [weak self] in
                self?.finishRendering(result, generation: requestGeneration)
            }
        }
    }

    func stop() {
        generation &+= 1
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        playerNode.stop()
        audioEngine.pause()
        activeItemID = nil
        activeAudioFile = nil
        removeActiveTemporaryFile()
    }

    private func finishRendering(_ result: SpeechRenderResult, generation: Int) {
        guard generation == self.generation, activeItemID != nil else {
            if case .success(let url) = result { try? FileManager.default.removeItem(at: url) }
            return
        }
        switch result {
        case .success(let url):
            playRenderedAudio(at: url, generation: generation)
        case .failure:
            finishPlayback(generation: generation)
        }
    }

    private func playRenderedAudio(at url: URL, generation: Int) {
        do {
            let file = try AVAudioFile(forReading: url)
            activeAudioFile = file
            activeTemporaryURL = url
            timePitch.rate = Float(rate.rawValue)
            playerNode.scheduleFile(
                file,
                at: nil,
                completionCallbackType: .dataPlayedBack,
                completionHandler: playbackCompletionHandler(generation: generation)
            )
            audioEngine.prepare()
            if !audioEngine.isRunning { try audioEngine.start() }
            playerNode.play()
        } catch {
            try? FileManager.default.removeItem(at: url)
            finishPlayback(generation: generation)
        }
    }

    // AVAudioPlayerNode invokes completion handlers on its private queue. Building
    // the handler in a nonisolated context prevents Swift from attaching a
    // MainActor executor precondition to that callback; the state update itself
    // is then explicitly handed back to the main actor.
    private nonisolated func playbackCompletionHandler(
        generation: Int
    ) -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
        { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finishPlayback(generation: generation)
            }
        }
    }

    private func finishPlayback(generation: Int) {
        guard generation == self.generation else { return }
        playerNode.stop()
        audioEngine.pause()
        activeItemID = nil
        activeAudioFile = nil
        removeActiveTemporaryFile()
    }

    private func removeActiveTemporaryFile() {
        if let activeTemporaryURL {
            try? FileManager.default.removeItem(at: activeTemporaryURL)
        }
        activeTemporaryURL = nil
    }
}

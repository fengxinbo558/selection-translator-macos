import SwiftUI

struct SpeechRatePicker: View {
    @ObservedObject var speech: SpeechPlaybackController

    var body: some View {
        Menu {
            ForEach(SpeechRate.allCases) { rate in
                Button {
                    speech.setRate(rate)
                } label: {
                    if rate == speech.rate {
                        Label(rate.displayName, systemImage: "checkmark")
                    } else {
                        Text(rate.displayName)
                    }
                }
            }
        } label: {
            Label(speech.rate.displayName, systemImage: "speedometer")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("朗读速度")
        .help("调整原文和译文的朗读速度")
    }
}

struct TranslationSpeechButton: View {
    @ObservedObject var speech: SpeechPlaybackController
    let itemID: String
    let title: String
    let text: String
    let languageIdentifier: String?

    var body: some View {
        let isSpeaking = speech.isSpeaking(itemID: itemID)
        Button {
            speech.toggle(
                itemID: itemID,
                text: text,
                languageIdentifier: languageIdentifier
            )
        } label: {
            Label(
                isSpeaking ? "停止" : title,
                systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help(isSpeaking ? "停止\(title)" : title)
    }
}

struct AbbreviationExplanationButton: View {
    let explanation: AbbreviationExplanation
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("解释缩写", systemImage: "info.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("查看英文全称、中文含义和用途")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AbbreviationExplanationCard(explanation: explanation)
        }
    }
}

private struct AbbreviationExplanationCard: View {
    let explanation: AbbreviationExplanation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(explanation.abbreviation)
                    .font(.title3.bold())
                Text("缩写解释")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("英文全称")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(explanation.fullName)
                    .font(.system(size: 14, weight: .medium))
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("中文含义")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(explanation.chineseMeaning)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("用途")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(explanation.usage)
                    .font(.system(size: 13.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }
}

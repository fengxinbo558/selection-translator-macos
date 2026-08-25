import Foundation
import Testing
@testable import Huayi

@Suite("AI translation service")
struct AITranslationServiceTests {
    @Test func decodesChatCompletionDelta() throws {
        let event = #"{"choices":[{"delta":{"content":"Hello"}}]}"#
        #expect(try AITranslationService.decodeEventData(event, provider: .deepSeek) == "Hello")
    }

    @Test func decodesOpenAIResponsesDelta() throws {
        let event = #"{"type":"response.output_text.delta","delta":"Hello"}"#
        #expect(try AITranslationService.decodeEventData(event, provider: .openAI) == "Hello")
    }

    @Test func decodesAnthropicDelta() throws {
        let event = #"{"delta":{"type":"text_delta","text":"Hello"}}"#
        #expect(try AITranslationService.decodeEventData(event, provider: .anthropic) == "Hello")
    }

    @Test func decodesGeminiAndSkipsThoughts() throws {
        let event = #"{"candidates":[{"content":{"parts":[{"text":"hidden","thought":true},{"text":"Hello"}]}}]}"#
        #expect(try AITranslationService.decodeEventData(event, provider: .gemini) == "Hello")
    }

    @Test func compatibleURLRequiresHTTPSAndRejectsSensitiveQuery() throws {
        #expect(throws: AITranslationError.self) {
            try AITranslationService.validatedCompatibleURL("http://example.com/v1/chat")
        }
        #expect(throws: AITranslationError.self) {
            try AITranslationService.validatedCompatibleURL(
                "https://example.com/v1/chat?api_key=secret"
            )
        }
        let valid = try AITranslationService.validatedCompatibleURL(
            "https://example.com/v1/chat/completions"
        )
        #expect(valid.host == "example.com")
    }
}

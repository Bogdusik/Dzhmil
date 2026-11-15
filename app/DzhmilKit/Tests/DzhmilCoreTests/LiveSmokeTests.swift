import Foundation
import Testing
@testable import DzhmilCore

@Suite struct LiveSmokeTests {
    static var key: String? { ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] }

    @Test(.enabled(if: key != nil)) func haikuSaysHello() async throws {
        let client = URLSessionClaudeClient(apiKey: { LiveSmokeTests.key })
        let request = MessagesRequest(model: "claude-haiku-5-5", system: "Отвечай одним словом.", messages: [["role": "user", "content": "Скажи привет одним словом"]], tools: [], effort: "low", maxTokens: 1024)
        var final: AssistantMessage?
        for try await e in client.stream(request) {
            if case .message(let m) = e { final = m }
        }
        #expect(!(final?.text.isEmpty ?? true))
    }
}

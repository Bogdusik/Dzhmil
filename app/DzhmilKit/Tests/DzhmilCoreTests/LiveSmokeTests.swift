import Foundation
import Testing
@testable import DzhmilCore

@Suite struct LiveSmokeTests {
    static var key: String? { ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] }

    @Test(.enabled(if: key != nil)) func haikuSaysHello() async throws {
        let client = AnthropicClient(apiKey: { LiveSmokeTests.key })
        let request = MessagesRequest(model: "claude-haiku-5-5", system: "Answer in one word.", messages: [["role": "user", "content": "Say hello in one word"]], tools: [], effort: "low", maxTokens: 1024)
        var final: AssistantMessage?
        for try await e in client.stream(request) {
            if case .message(let m) = e { final = m }
        }
        #expect(!(final?.text.isEmpty ?? true))
    }
}

@Suite struct OllamaSmokeTests {
    static var model: String? { ProcessInfo.processInfo.environment["OLLAMA_MODEL"] }

    func run(_ request: MessagesRequest) async throws -> AssistantMessage? {
        var final: AssistantMessage?
        for try await e in RoutingClient(apiKey: { _ in nil }).stream(request) {
            if case .message(let m) = e { final = m }
        }
        return final
    }

    @Test(.enabled(if: model != nil)) func callsAToolAndReadsTheResult() async throws {
        let tool: JSONValue = ["name": "get_battery", "description": "Returns the Mac's battery level.",
                               "input_schema": ["type": "object", "properties": [:], "required": [], "additionalProperties": false]]
        var messages: [JSONValue] = [["role": "user", "content": "What is my battery level? Use the tool."]]
        let request = { MessagesRequest(model: OllamaSmokeTests.model!, system: "You are a helpful Mac assistant.", messages: messages,
                                        tools: [tool], effort: "low", provider: .ollama) }
        let first = try #require(try await run(request()))
        let use = try #require(first.toolUses.first)
        #expect(use.name == "get_battery")
        messages.append(first.asHistoryEntry)
        messages.append(["role": "user", "content": [["type": "tool_result", "tool_use_id": .string(use.id), "content": "Battery: 42%, charging"]]])
        let second = try #require(try await run(request()))
        #expect(second.toolUses.isEmpty)
        #expect(second.text.contains("42"))
    }
}

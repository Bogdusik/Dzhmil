import Foundation
import Testing
@testable import DzhmilCore

@Suite struct MessagesRequestTests {
    @Test func opusBodyHasFallbacksAndNoThinking() throws {
        let r = MessagesRequest(model: "claude-opus-5-5", system: "S", messages: [], tools: [], effort: "low")
        let b = try JSONDecoder().decode(JSONValue.self, from: r.body())
        #expect(b["model"] == "claude-opus-5-5")
        #expect(b["stream"] == .bool(true))
        #expect(b["max_tokens"] == .number(16000))
        #expect(b["output_config"]?["effort"] == .string("low"))
        #expect(b["cache_control"]?["type"] == .string("ephemeral"))
        #expect(b["fallbacks"] == .string("default"))
        #expect(b["system"]?.stringValue == "S")
        #expect(b["thinking"] == nil)
        #expect(b["temperature"] == nil)
        #expect(b["tool_choice"] == nil)
        let h = r.headers(apiKey: "k")
        #expect(h["anthropic-beta"] == "server-side-fallback-2026-07-01")
        #expect(h["anthropic-version"] == "2026-10-21")
        #expect(h["x-api-key"] == "k")
        #expect(h["content-type"] == "application/json")
    }

    @Test func haikuHasNoFallbacks() throws {
        let r = MessagesRequest(model: "claude-haiku-5-5", system: "S", messages: [], tools: [], effort: "low")
        let b = try JSONDecoder().decode(JSONValue.self, from: r.body())
        #expect(b["fallbacks"] == nil)
        #expect(r.headers(apiKey: "k")["anthropic-beta"] == nil)
    }

    @Test func messagesAndToolsPassThrough() throws {
        let msg: JSONValue = ["role": "user", "content": "hi"]
        let tool: JSONValue = ["name": "t", "description": "d", "input_schema": ["type": "object"]]
        let r = MessagesRequest(model: "claude-opus-5-5", system: "S", messages: [msg], tools: [tool], effort: "low")
        let b = try JSONDecoder().decode(JSONValue.self, from: r.body())
        #expect(b["messages"] == .array([msg]))
        #expect(b["tools"] == .array([tool]))
    }

    @Test func bodyIsByteStable() throws {
        let r = MessagesRequest(model: "claude-opus-5-5", system: "S", messages: [["role": "user", "content": "x"]], tools: [], effort: "low")
        #expect(try r.body() == r.body())
    }
}

import Foundation
import Testing
@testable import DzhmilCore

@Suite struct ProviderTests {
    @Test func detectsProviderFromKey() {
        #expect(Provider.detect(key: " sk-ant-api03-abc ") == .anthropic)
        #expect(Provider.detect(key: "sk-or-v1-abc") == .openrouter)
        #expect(Provider.detect(key: "AIzaSyAbc") == .gemini)
        #expect(Provider.detect(key: "sk-proj-abc") == .openai)
        #expect(Provider.detect(key: "hello") == nil)
    }

    @Test func endpointsMatchTheWire() {
        #expect(Provider.anthropic.endpoint.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(Provider.openai.endpoint.absoluteString == "https://api.openai.com/v1/responses")
        #expect(Provider.gemini.endpoint.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        #expect(Provider.openrouter.endpoint.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(Provider.ollama.endpoint.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(Provider.ollama.modelsEndpoint.absoluteString == "http://localhost:11434/v1/models")
    }

    @Test func anthropicKeepsItsOldKeychainAccount() {
        #expect(Provider.anthropic.keyAccount == KeychainStore().account)
        #expect(Set(Provider.allCases.map(\.keyAccount)).count == Provider.allCases.count)
        #expect(!Provider.ollama.needsKey)
    }

    @Test func modelListDropsNonChatModels() {
        let body = #"{"data":[{"id":"models/gemini-4-hydrogen"},{"id":"gpt-6.2-sol"},{"id":"text-embedding-3-large"},{"id":"gpt-image-2"},{"id":"gpt-6.2-sol"}]}"#
        #expect(ModelCatalog.ids(in: body) == ["gemini-4-hydrogen", "gpt-6.2-sol"])
    }
}

@Suite struct ProviderSettingsTests {
    @Test func eachProviderRemembersItsModel() {
        var s = AppSettings()
        s.model = "claude-haiku-5-5"
        s.provider = .openai
        #expect(s.model == "gpt-6.2-sol")
        s.model = "gpt-6-luna"
        s.provider = .anthropic
        #expect(s.model == "claude-haiku-5-5")
        s.provider = .openai
        #expect(s.model == "gpt-6-luna")
        #expect(s.conversation == ConversationSettings(model: "gpt-6-luna", effort: "low", provider: .openai))
    }

    @Test func emptyModelFallsBackToDefault() {
        var s = AppSettings()
        s.provider = .ollama
        s.model = "  "
        #expect(s.model == "qwen3")
    }

    @Test func roundTripsAndReadsOldSettings() throws {
        var s = AppSettings()
        s.provider = .gemini
        s.model = "gemini-4-carbon"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
        #expect(decoded.model == "gemini-4-carbon")

        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"model":"claude-sonnet-5-5"}"#.utf8))
        #expect(old.provider == .anthropic)
        #expect(old.model == "claude-sonnet-5-5")
    }
}

@Suite struct ResponsesWireTests {
    let image: JSONValue = ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": "AAAA"]]

    func body(_ messages: [JSONValue], tools: [JSONValue] = []) throws -> JSONValue {
        let r = MessagesRequest(model: "gpt-6.2-sol", system: "SYS", messages: messages, tools: tools, effort: "medium", provider: .openai)
        return try JSONDecoder().decode(JSONValue.self, from: ResponsesWire.body(r))
    }

    @Test func requestShape() throws {
        let tool: JSONValue = ["name": "open_app", "description": "Opens an app", "strict": true,
                               "input_schema": ["type": "object", "properties": ["app": ["type": "string"]], "required": ["app"], "additionalProperties": false]]
        let b = try body([["role": "user", "content": "hi"]], tools: [tool])
        #expect(b["model"] == "gpt-6.2-sol")
        #expect(b["instructions"] == "SYS")
        #expect(b["stream"] == true)
        #expect(b["store"] == false)
        #expect(b["include"] == ["reasoning.encrypted_content"])
        #expect(b["reasoning"] == ["effort": "medium"])
        #expect(b["input"] == [["role": "user", "content": "hi"]])
        #expect(b["tools"] == [["type": "function", "name": "open_app", "description": "Opens an app", "strict": false,
                                "parameters": ["type": "object", "properties": ["app": ["type": "string"]], "required": ["app"], "additionalProperties": false]]])
    }

    @Test func toolRoundTripKeepsReasoningAndImages() throws {
        let reasoning: JSONValue = ["type": "reasoning", "id": "rs_1", "summary": [], "encrypted_content": "enc"]
        let history: [JSONValue] = [
            ["role": "user", "content": "what's on screen?"],
            ["role": "assistant", "content": [
                ["type": OpenAIWire.reasoningBlock.json, "item": reasoning],
                ["type": "text", "text": "Let me look."],
                ["type": "tool_use", "id": "call_1", "name": "look_at_screen", "input": [:]],
            ]],
            ["role": "user", "content": [
                ["type": "tool_result", "tool_use_id": "call_1", "content": [image, ["type": "text", "text": "Screen 1"]]],
                ["type": "text", "text": "and now?"],
            ]],
        ]
        let input = try body(history)["input"]?.arrayValue ?? []
        #expect(input == [
            ["role": "user", "content": "what's on screen?"],
            reasoning,
            ["role": "assistant", "content": "Let me look."],
            ["type": "function_call", "call_id": "call_1", "name": "look_at_screen", "arguments": "{}"],
            ["type": "function_call_output", "call_id": "call_1", "output": [
                ["type": "input_image", "image_url": "data:image/jpeg;base64,AAAA"],
                ["type": "input_text", "text": "Screen 1"],
            ]],
            ["role": "user", "content": [["type": "input_text", "text": "and now?"]]],
        ])
    }

    @Test func thinkingFromClaudeIsDropped() throws {
        let input = try body([["role": "assistant", "content": [["type": "thinking", "thinking": "", "signature": "s"], ["type": "text", "text": "Hi"]]]])["input"]
        #expect(input == [["role": "assistant", "content": "Hi"]])
    }

    func decode(_ events: [String]) throws -> (deltas: [String], message: AssistantMessage) {
        var d = ResponsesDecoder()
        var deltas: [String] = []
        for e in events {
            if let t = try d.consume(SSEEvent(event: nil, data: e)) { deltas.append(t) }
        }
        return (deltas, try d.finish())
    }

    @Test func decodesTextAndToolCalls() throws {
        let (deltas, m) = try decode([
            #"{"type":"response.created","response":{"status":"in_progress"}}"#,
            #"{"type":"response.output_text.delta","delta":"Opening "}"#,
            #"{"type":"response.output_text.delta","delta":"Safari."}"#,
            #"{"type":"response.function_call_arguments.delta","delta":"{\"app\""}"#,
            #"{"type":"response.completed","response":{"status":"completed","output":[{"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":"enc"},{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Opening Safari.","annotations":[]}]},{"type":"function_call","id":"fc_1","call_id":"call_9","name":"open_app","arguments":"{\"app\":\"Safari\"}"}]}}"#,
        ])
        #expect(deltas == ["Opening ", "Safari."])
        #expect(m.stopReason == "tool_use")
        #expect(m.text == "Opening Safari.")
        #expect(m.toolUses == [ToolUse(id: "call_9", name: "open_app", input: ["app": "Safari"])])
        #expect(m.content.first?["type"] == OpenAIWire.reasoningBlock.json)
    }

    @Test func plainAnswerEndsTheTurn() throws {
        let (_, m) = try decode([
            #"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","content":[{"type":"output_text","text":"Hi!"}]}}"#,
            #"{"type":"response.completed","response":{"status":"completed"}}"#,
        ])
        #expect(m.stopReason == "end_turn")
        #expect(m.content == [["type": "text", "text": "Hi!"]])
    }

    @Test func failuresAreErrors() {
        #expect(throws: ChatError.incomplete) { try decode([#"{"type":"response.output_text.delta","delta":"Hi"}"#]) }
        #expect(throws: ChatError.refusal) {
            try decode([#"{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"No."}]}]}}"#])
        }
        #expect(throws: ChatError.rateLimited) { try decode([#"{"type":"error","code":"rate_limit_exceeded","message":"slow down"}"#]) }
        #expect(throws: ChatError.insufficientCredit) {
            try decode([#"{"type":"response.failed","response":{"status":"failed","error":{"code":"insufficient_quota","message":"quota"}}}"#])
        }
    }
}

@Suite struct ChatCompletionsWireTests {
    let image: JSONValue = ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": "BBBB"]]

    func body(_ messages: [JSONValue], provider: Provider = .openrouter, tools: [JSONValue] = []) throws -> JSONValue {
        let r = MessagesRequest(model: "m", system: "SYS", messages: messages, tools: tools, effort: "high", provider: provider)
        return try JSONDecoder().decode(JSONValue.self, from: ChatCompletionsWire.body(r))
    }

    @Test func requestShape() throws {
        let b = try body([["role": "user", "content": "hi"]])
        #expect(b["model"] == "m")
        #expect(b["stream"] == true)
        #expect(b["messages"] == [["role": "system", "content": "SYS"], ["role": "user", "content": "hi"]])
        #expect(b["reasoning_effort"] == nil)
        #expect(try body([], provider: .gemini)["reasoning_effort"] == "high")
    }

    @Test func toolResultsBecomeToolMessagesWithImagesAfter() throws {
        let history: [JSONValue] = [
            ["role": "assistant", "content": [
                ["type": "tool_use", "id": "c1", "name": "look_at_screen", "input": [:], "extra_content": ["google": ["thought_signature": "sig"]]],
                ["type": "tool_use", "id": "c2", "name": "open_app", "input": ["app": "Notes"]],
            ]],
            ["role": "user", "content": [
                ["type": "tool_result", "tool_use_id": "c1", "content": [image, ["type": "text", "text": "Screen 1"]]],
                ["type": "tool_result", "tool_use_id": "c2", "content": "Opened", "is_error": false],
            ]],
            ["role": "assistant", "content": [["type": "text", "text": "Done."]]],
            ["role": "user", "content": [["type": "text", "text": "thanks"]]],
        ]
        let messages = try body(history)["messages"]?.arrayValue ?? []
        #expect(Array(messages.dropFirst()) == [
            ["role": "assistant", "content": nil, "tool_calls": [
                ["id": "c1", "type": "function", "function": ["name": "look_at_screen", "arguments": "{}"], "extra_content": ["google": ["thought_signature": "sig"]]],
                ["id": "c2", "type": "function", "function": ["name": "open_app", "arguments": #"{"app":"Notes"}"#]],
            ]],
            ["role": "tool", "tool_call_id": "c1", "content": "Screen 1\n(The image is attached in the next message.)"],
            ["role": "tool", "tool_call_id": "c2", "content": "Opened"],
            ["role": "user", "content": [["type": "image_url", "image_url": ["url": "data:image/png;base64,BBBB"]]]],
            ["role": "assistant", "content": "Done."],
            ["role": "user", "content": "thanks"],
        ])
    }

    @Test func geminiGetsAPlainSchema() throws {
        let withArgs: JSONValue = ["name": "open_app", "description": "d", "strict": true,
                                   "input_schema": ["type": "object", "properties": ["app": ["type": "string"]], "required": ["app"], "additionalProperties": false]]
        let noArgs: JSONValue = ["name": "lock", "description": "d", "input_schema": ["type": "object", "properties": [:], "required": [], "additionalProperties": false]]
        let gemini = try body([], provider: .gemini, tools: [withArgs, noArgs])["tools"]
        #expect(gemini == [
            ["type": "function", "function": ["name": "open_app", "description": "d", "parameters": ["type": "object", "properties": ["app": ["type": "string"]], "required": ["app"]]]],
            ["type": "function", "function": ["name": "lock", "description": "d"]],
        ])
        let other = try body([], provider: .ollama, tools: [noArgs])["tools"]
        #expect(other == [["type": "function", "function": ["name": "lock", "description": "d", "parameters": noArgs["input_schema"]!]]])
    }

    func decode(_ events: [String]) throws -> (deltas: [String], message: AssistantMessage) {
        var d = ChatCompletionsDecoder()
        var deltas: [String] = []
        for e in events {
            if let t = try d.consume(SSEEvent(event: nil, data: e)) { deltas.append(t) }
        }
        return (deltas, try d.finish())
    }

    @Test func decodesStreamedToolCalls() throws {
        let (deltas, m) = try decode([
            #"{"choices":[{"index":0,"delta":{"role":"assistant","content":"On it."}}]}"#,
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"open_app","arguments":""}}]}}]}"#,
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"app\":"}}]}}]}"#,
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"Notes\"}"}}]}}]}"#,
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"id":"call_b","function":{"name":"lock","arguments":""}}]}}]}"#,
            #"{"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#,
            "[DONE]",
        ])
        #expect(deltas == ["On it."])
        #expect(m.stopReason == "tool_use")
        #expect(m.text == "On it.")
        #expect(m.toolUses == [ToolUse(id: "call_a", name: "open_app", input: ["app": "Notes"]), ToolUse(id: "call_b", name: "lock", input: [:])])
    }

    @Test func geminiStyleCallsWithoutIndexOrIDStillWork() throws {
        let (_, m) = try decode([
            #"{"choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"function":{"name":"open_app","arguments":"{\"app\":\"Notes\"}"},"type":"function","extra_content":{"google":{"thought_signature":"sig"}}}]},"finish_reason":"stop"}]}"#,
            "[DONE]",
        ])
        #expect(m.stopReason == "tool_use")
        let use = try #require(m.toolUses.first)
        #expect(use.name == "open_app")
        #expect(use.input == ["app": "Notes"])
        #expect(use.id.hasPrefix("call_"))
        #expect(m.content.last?["extra_content"] == ["google": ["thought_signature": "sig"]])
    }

    @Test func plainReplyAndFailures() throws {
        let (_, m) = try decode([#"{"choices":[{"delta":{"content":"Hi!"},"finish_reason":"stop"}]}"#, "[DONE]"])
        #expect(m.stopReason == "end_turn")
        #expect(m.content == [["type": "text", "text": "Hi!"]])
        #expect(try decode([#"{"choices":[{"delta":{"content":"Hi"},"finish_reason":"length"}]}"#]).message.stopReason == "max_tokens")
        #expect(throws: ChatError.incomplete) { try decode([#"{"choices":[{"delta":{"content":"Hi"}}]}"#]) }
        #expect(throws: ChatError.refusal) { try decode([#"{"choices":[{"delta":{},"finish_reason":"content_filter"}]}"#]) }
        #expect(throws: ChatError.rateLimited) { try decode([#"{"error":{"message":"slow","code":"rate_limit_exceeded"}}"#]) }
    }
}

@Suite struct ProviderSwitchTests {
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: ConversationSettings
        init(_ v: ConversationSettings) { _value = v }
        var value: ConversationSettings {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }

    @Test func switchingProviderStartsAFreshSession() async {
        let box = Box(ConversationSettings(model: "claude-opus-5-5", effort: "low"))
        let client = FakeChatClient([Fixtures.text("One."), Fixtures.text("Two."), Fixtures.text("Three.")])
        let conv = Conversation(client: client, executor: ToolExecutor(tools: [], confirmer: ScriptedConfirmer(mode: .yes)),
                                settings: { box.value }, profile: { "" })
        for await _ in await conv.send("a") {}
        for await _ in await conv.send("b") {}
        #expect(await conv.history.count == 4)
        box.value = ConversationSettings(model: "gpt-6.2-sol", effort: "low", provider: .openai)
        for await _ in await conv.send("c") {}
        #expect(await conv.history.count == 2)
        #expect(client.requests.map(\.provider) == [.anthropic, .anthropic, .openai])
        #expect(client.requests.last?.model == "gpt-6.2-sol")
    }
}

private extension String {
    var json: JSONValue { .string(self) }
}

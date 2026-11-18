import Foundation

enum OpenAIWire {
    static let reasoningBlock = "openai_reasoning"
    static let extraContent = "extra_content"

    static func dataURL(_ image: JSONValue) -> String? {
        guard let source = image["source"], let media = source["media_type"]?.stringValue,
              let data = source["data"]?.stringValue else { return nil }
        return "data:\(media);base64,\(data)"
    }

    static func arguments(_ input: JSONValue?) -> String {
        (try? (input ?? .object([:])).encodedString()) ?? "{}"
    }

    static func toolUse(id: String?, name: String, arguments: String, extra: JSONValue? = nil) -> JSONValue {
        let input = (try? JSONValue.parse(arguments)).flatMap { value -> JSONValue? in
            if case .object = value { return value }
            return nil
        } ?? .object([:])
        let callID = id.flatMap { $0.isEmpty ? nil : $0 } ?? "call_\(UUID().uuidString.prefix(12).lowercased())"
        var block: [String: JSONValue] = ["type": "tool_use", "id": .string(callID), "name": .string(name), "input": input]
        if let extra { block[extraContent] = extra }
        return .object(block)
    }

    static func resultText(_ content: JSONValue?) -> String {
        if case .string(let s)? = content { return s }
        return (content?.arrayValue ?? []).compactMap { $0["type"] == "text" ? $0["text"]?.stringValue : nil }.joined(separator: "\n")
    }

    static func resultImages(_ content: JSONValue?) -> [String] {
        (content?.arrayValue ?? []).compactMap { $0["type"] == "image" ? dataURL($0) : nil }
    }
}

enum ResponsesWire {
    static func body(_ r: MessagesRequest) throws -> Data {
        var b: [String: JSONValue] = [
            "model": .string(r.model),
            "instructions": .string(r.system),
            "input": .array(input(r.messages)),
            "stream": true,
            "store": false,
            "include": ["reasoning.encrypted_content"],
        ]
        if r.provider.sendsEffort { b["reasoning"] = ["effort": .string(r.effort)] }
        if !r.tools.isEmpty { b["tools"] = .array(r.tools.map(tool)) }
        return try JSONValue.object(b).encodedData()
    }

    static func tool(_ t: JSONValue) -> JSONValue {
        ["type": "function", "name": t["name"] ?? "", "description": t["description"] ?? "",
         "parameters": t["input_schema"] ?? .object([:]), "strict": false]
    }

    static func input(_ messages: [JSONValue]) -> [JSONValue] {
        var out: [JSONValue] = []
        for m in messages {
            let role = m["role"]?.stringValue ?? "user"
            if case .string(let text)? = m["content"] {
                out.append(["role": .string(role), "content": .string(text)])
                continue
            }
            let blocks = m["content"]?.arrayValue ?? []
            if role == "assistant" {
                var text = ""
                func flush() {
                    if !text.isEmpty { out.append(["role": "assistant", "content": .string(text)]) }
                    text = ""
                }
                for b in blocks {
                    switch b["type"]?.stringValue {
                    case "text":
                        text += b["text"]?.stringValue ?? ""
                    case "tool_use":
                        flush()
                        out.append(["type": "function_call", "call_id": b["id"] ?? "", "name": b["name"] ?? "",
                                    "arguments": .string(OpenAIWire.arguments(b["input"]))])
                    case OpenAIWire.reasoningBlock:
                        flush()
                        if let item = b["item"] { out.append(item) }
                    default:
                        break
                    }
                }
                flush()
            } else {
                var parts: [JSONValue] = []
                for b in blocks {
                    switch b["type"]?.stringValue {
                    case "text":
                        parts.append(["type": "input_text", "text": b["text"] ?? ""])
                    case "image":
                        if let url = OpenAIWire.dataURL(b) { parts.append(["type": "input_image", "image_url": .string(url)]) }
                    case "tool_result":
                        out.append(["type": "function_call_output", "call_id": b["tool_use_id"] ?? "", "output": output(b["content"])])
                    default:
                        break
                    }
                }
                if !parts.isEmpty { out.append(["role": "user", "content": .array(parts)]) }
            }
        }
        return out
    }

    static func output(_ content: JSONValue?) -> JSONValue {
        let images = OpenAIWire.resultImages(content)
        let text = OpenAIWire.resultText(content)
        guard !images.isEmpty else { return .string(text) }
        var parts: [JSONValue] = images.map { ["type": "input_image", "image_url": .string($0)] }
        parts.append(["type": "input_text", "text": .string(text)])
        return .array(parts)
    }
}

struct ResponsesDecoder: StreamDecoder {
    private var items: [Int: JSONValue] = [:]
    private var output: [JSONValue]?
    private var status: String?
    private var incompleteReason: String?

    mutating func consume(_ e: SSEEvent) throws -> String? {
        guard let p = try? JSONValue.parse(e.data), let type = p["type"]?.stringValue else { return nil }
        switch type {
        case "response.output_text.delta":
            let d = p["delta"]?.stringValue ?? ""
            return d.isEmpty ? nil : d
        case "response.output_item.done":
            if let i = p["output_index"]?.intValue, let item = p["item"] { items[i] = item }
        case "response.completed", "response.incomplete":
            let response = p["response"]
            status = response?["status"]?.stringValue ?? (type == "response.completed" ? "completed" : "incomplete")
            incompleteReason = response?["incomplete_details"]?["reason"]?.stringValue
            if let out = response?["output"]?.arrayValue, !out.isEmpty { output = out }
        case "response.failed":
            throw ChatError.fromOpenAIStream(p["response"]?["error"])
        case "error":
            throw ChatError.fromOpenAIStream(p["error"] ?? p)
        default:
            break
        }
        return nil
    }

    func finish() throws -> AssistantMessage {
        guard let status else { throw ChatError.incomplete }
        if incompleteReason == "content_filter" { throw ChatError.refusal }
        var content: [JSONValue] = []
        var calls = false
        for item in output ?? items.keys.sorted().compactMap({ items[$0] }) {
            switch item["type"]?.stringValue {
            case "reasoning":
                content.append(["type": .string(OpenAIWire.reasoningBlock), "item": item])
            case "message":
                for part in item["content"]?.arrayValue ?? [] {
                    if part["type"] == "refusal" { throw ChatError.refusal }
                    if part["type"] == "output_text", let t = part["text"]?.stringValue, !t.isEmpty {
                        content.append(["type": "text", "text": .string(t)])
                    }
                }
            case "function_call":
                calls = true
                content.append(OpenAIWire.toolUse(id: item["call_id"]?.stringValue, name: item["name"]?.stringValue ?? "",
                                                  arguments: item["arguments"]?.stringValue ?? "{}"))
            default:
                break
            }
        }
        let stop = calls ? "tool_use" : status == "incomplete" ? "max_tokens" : "end_turn"
        return AssistantMessage(content: content, stopReason: stop)
    }
}

enum ChatCompletionsWire {
    static func body(_ r: MessagesRequest) throws -> Data {
        var b: [String: JSONValue] = [
            "model": .string(r.model),
            "messages": .array([["role": "system", "content": .string(r.system)]] + messages(r.messages)),
            "stream": true,
        ]
        if r.provider.sendsEffort { b["reasoning_effort"] = .string(r.effort) }
        if !r.tools.isEmpty { b["tools"] = .array(r.tools.map { tool($0, for: r.provider) }) }
        return try JSONValue.object(b).encodedData()
    }

    static func tool(_ t: JSONValue, for provider: Provider) -> JSONValue {
        var function: [String: JSONValue] = ["name": t["name"] ?? "", "description": t["description"] ?? ""]
        let schema = t["input_schema"] ?? .object([:])
        if provider == .gemini {
            if let clean = geminiSchema(schema) { function["parameters"] = clean }
        } else {
            function["parameters"] = schema
        }
        return ["type": "function", "function": .object(function)]
    }

    static func geminiSchema(_ schema: JSONValue) -> JSONValue? {
        func clean(_ v: JSONValue) -> JSONValue {
            switch v {
            case .object(let o):
                var out = o.filter { $0.key != "additionalProperties" && $0.key != "strict" }.mapValues(clean)
                if out["required"]?.arrayValue?.isEmpty == true { out["required"] = nil }
                return .object(out)
            case .array(let a):
                return .array(a.map(clean))
            default:
                return v
            }
        }
        if case .object(let props)? = schema["properties"], props.isEmpty { return nil }
        return clean(schema)
    }

    static func messages(_ history: [JSONValue]) -> [JSONValue] {
        var out: [JSONValue] = []
        for m in history {
            let role = m["role"]?.stringValue ?? "user"
            if case .string(let text)? = m["content"] {
                out.append(["role": .string(role), "content": .string(text)])
                continue
            }
            let blocks = m["content"]?.arrayValue ?? []
            if role == "assistant" {
                let text = blocks.compactMap { $0["type"] == "text" ? $0["text"]?.stringValue : nil }.joined()
                let calls: [JSONValue] = blocks.compactMap { b in
                    guard b["type"] == "tool_use" else { return nil }
                    var call: [String: JSONValue] = ["id": b["id"] ?? "", "type": "function",
                                                     "function": ["name": b["name"] ?? "", "arguments": .string(OpenAIWire.arguments(b["input"]))]]
                    if let extra = b[OpenAIWire.extraContent] { call[OpenAIWire.extraContent] = extra }
                    return .object(call)
                }
                var message: [String: JSONValue] = ["role": "assistant", "content": text.isEmpty && !calls.isEmpty ? .null : .string(text)]
                if !calls.isEmpty { message["tool_calls"] = .array(calls) }
                out.append(.object(message))
            } else {
                var parts: [JSONValue] = []
                for b in blocks {
                    switch b["type"]?.stringValue {
                    case "text":
                        parts.append(["type": "text", "text": b["text"] ?? ""])
                    case "image":
                        if let url = OpenAIWire.dataURL(b) { parts.append(imagePart(url)) }
                    case "tool_result":
                        let images = OpenAIWire.resultImages(b["content"])
                        var text = OpenAIWire.resultText(b["content"])
                        if !images.isEmpty { text += "\n(The image is attached in the next message.)" }
                        out.append(["role": "tool", "tool_call_id": b["tool_use_id"] ?? "", "content": .string(text)])
                        parts += images.map(imagePart)
                    default:
                        break
                    }
                }
                guard !parts.isEmpty else { continue }
                let texts = parts.compactMap { $0["type"] == "text" ? $0["text"]?.stringValue : nil }
                out.append(["role": "user", "content": texts.count == parts.count ? .string(texts.joined(separator: "\n")) : .array(parts)])
            }
        }
        return out
    }

    static func imagePart(_ url: String) -> JSONValue {
        ["type": "image_url", "image_url": ["url": .string(url)]]
    }
}

struct ChatCompletionsDecoder: StreamDecoder {
    private struct Call: Sendable {
        var id = ""
        var name = ""
        var arguments = ""
        var extra: JSONValue?
    }

    private var text = ""
    private var calls: [Int: Call] = [:]
    private var finishReason: String?
    private var done = false

    mutating func consume(_ e: SSEEvent) throws -> String? {
        if e.data.trimmingCharacters(in: .whitespaces) == "[DONE]" {
            done = true
            return nil
        }
        guard let p = try? JSONValue.parse(e.data) else { return nil }
        if let error = p["error"] { throw ChatError.fromOpenAIStream(error) }
        guard let choice = p["choices"]?.arrayValue?.first else { return nil }
        if let reason = choice["finish_reason"]?.stringValue { finishReason = reason }
        let delta = choice["delta"]
        for call in delta?["tool_calls"]?.arrayValue ?? [] {
            let id = call["id"]?.stringValue ?? ""
            let index = call["index"]?.intValue
                ?? calls.first(where: { !id.isEmpty && $0.value.id == id })?.key
                ?? (calls.keys.max() ?? -1) + 1
            var c = calls[index] ?? Call()
            if !id.isEmpty { c.id = id }
            if let name = call["function"]?["name"]?.stringValue, !name.isEmpty, c.name.isEmpty { c.name = name }
            c.arguments += call["function"]?["arguments"]?.stringValue ?? ""
            if let extra = call[OpenAIWire.extraContent] { c.extra = extra }
            calls[index] = c
        }
        guard let t = delta?["content"]?.stringValue, !t.isEmpty else { return nil }
        text += t
        return t
    }

    func finish() throws -> AssistantMessage {
        guard finishReason != nil || done else { throw ChatError.incomplete }
        if finishReason == "content_filter" { throw ChatError.refusal }
        var content: [JSONValue] = []
        if !text.isEmpty { content.append(["type": "text", "text": .string(text)]) }
        for i in calls.keys.sorted() {
            guard let c = calls[i], !c.name.isEmpty else { continue }
            content.append(OpenAIWire.toolUse(id: c.id, name: c.name, arguments: c.arguments.isEmpty ? "{}" : c.arguments, extra: c.extra))
        }
        let hasCalls = content.contains { $0["type"] == "tool_use" }
        let stop = hasCalls ? "tool_use" : finishReason == "length" ? "max_tokens" : "end_turn"
        return AssistantMessage(content: content, stopReason: stop)
    }
}

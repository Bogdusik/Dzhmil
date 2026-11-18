public struct ToolUse: Equatable, Sendable {
    public var id: String
    public var name: String
    public var input: JSONValue

    public init(id: String, name: String, input: JSONValue) {
        self.id = id
        self.name = name
        self.input = input
    }
}

public struct AssistantMessage: Equatable, Sendable {
    public var content: [JSONValue]
    public var stopReason: String?

    public init(content: [JSONValue], stopReason: String?) {
        self.content = content
        self.stopReason = stopReason
    }

    public var text: String {
        content.compactMap { $0["type"] == "text" ? $0["text"]?.stringValue : nil }.joined()
    }

    public var toolUses: [ToolUse] {
        content.compactMap { block in
            guard block["type"] == "tool_use",
                  let id = block["id"]?.stringValue,
                  let name = block["name"]?.stringValue else { return nil }
            return ToolUse(id: id, name: name, input: block["input"] ?? .object([:]))
        }
    }

    public var asHistoryEntry: JSONValue {
        ["role": "assistant", "content": .array(content)]
    }
}

public struct StreamAccumulator: StreamDecoder {
    private var blocks: [Int: [String: JSONValue]] = [:]
    private var partialJSON: [Int: String] = [:]
    private var stopReason: String?

    public init() {}

    public mutating func consume(_ e: SSEEvent) throws -> String? {
        guard let payload = try? JSONValue.parse(e.data), let type = payload["type"]?.stringValue else { return nil }
        switch type {
        case "content_block_start":
            guard let i = payload["index"]?.intValue, case .object(let block)? = payload["content_block"] else { return nil }
            blocks[i] = block
        case "content_block_delta":
            guard let i = payload["index"]?.intValue, let delta = payload["delta"] else { return nil }
            return apply(delta, to: i)
        case "content_block_stop":
            guard let i = payload["index"]?.intValue else { return nil }
            if let json = partialJSON.removeValue(forKey: i), !json.isEmpty {
                blocks[i]?["input"] = (try? JSONValue.parse(json)) ?? .object([:])
            }
        case "message_delta":
            if let reason = payload["delta"]?["stop_reason"]?.stringValue { stopReason = reason }
        case "error":
            let err = payload["error"]
            throw ChatError.fromStream(type: err?["type"]?.stringValue ?? "", message: err?["message"]?.stringValue ?? "")
        default:
            break
        }
        return nil
    }

    private mutating func apply(_ delta: JSONValue, to i: Int) -> String? {
        guard var block = blocks[i] else { return nil }
        func append(_ field: String) {
            block[field] = .string((block[field]?.stringValue ?? "") + (delta[field]?.stringValue ?? ""))
        }
        var emitted: String?
        switch delta["type"]?.stringValue {
        case "text_delta":
            append("text")
            let t = delta["text"]?.stringValue ?? ""
            emitted = t.isEmpty ? nil : t
        case "thinking_delta":
            append("thinking")
        case "signature_delta":
            append("signature")
        case "input_json_delta":
            partialJSON[i, default: ""] += delta["partial_json"]?.stringValue ?? ""
        default:
            break
        }
        blocks[i] = block
        return emitted
    }

    public func finish() throws -> AssistantMessage {
        if stopReason == "refusal" { throw ChatError.refusal }
        guard stopReason != nil else { throw ChatError.incomplete }
        let content = blocks.keys.sorted().compactMap { blocks[$0].map(JSONValue.object) }
        return AssistantMessage(content: content, stopReason: stopReason)
    }
}

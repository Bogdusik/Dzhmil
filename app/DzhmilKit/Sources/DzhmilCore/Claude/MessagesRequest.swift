import Foundation

public struct MessagesRequest: Sendable {
    public static let apiVersion = "2026-10-21"
    public static let fallbackBeta = "server-side-fallback-2026-07-01"

    public var model: String
    public var system: String
    public var messages: [JSONValue]
    public var tools: [JSONValue]
    public var effort: String
    public var maxTokens: Int
    public var provider: Provider

    public init(model: String, system: String, messages: [JSONValue], tools: [JSONValue], effort: String, maxTokens: Int = 16000,
                provider: Provider = .anthropic) {
        self.provider = provider
        self.model = model
        self.system = system
        self.messages = messages
        self.tools = tools
        self.effort = effort
        self.maxTokens = maxTokens
    }

    var usesFallbacks: Bool { !model.hasPrefix("claude-haiku") }

    public func body() throws -> Data {
        var b: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .number(Double(maxTokens)),
            "stream": true,
            "system": .string(system),
            "messages": .array(messages),
            "output_config": ["effort": .string(effort)],
            "cache_control": ["type": "ephemeral"],
        ]
        if !tools.isEmpty { b["tools"] = .array(tools) }
        if usesFallbacks { b["fallbacks"] = "default" }
        return try JSONValue.object(b).encodedData()
    }

    public func headers(apiKey: String) -> [String: String] {
        var h = [
            "x-api-key": apiKey,
            "anthropic-version": Self.apiVersion,
            "content-type": "application/json",
        ]
        if usesFallbacks { h["anthropic-beta"] = Self.fallbackBeta }
        return h
    }
}

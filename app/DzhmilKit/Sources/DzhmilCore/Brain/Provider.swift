import Foundation

public enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic, openai, gemini, openrouter, ollama

    public enum Wire: Sendable {
        case anthropic, responses, chatCompletions
    }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .anthropic: "Claude (Anthropic)"
        case .openai: "ChatGPT (OpenAI)"
        case .gemini: "Gemini (Google)"
        case .openrouter: "OpenRouter (many models)"
        case .ollama: "Ollama (on this Mac)"
        }
    }

    public var wire: Wire {
        switch self {
        case .anthropic: .anthropic
        case .openai: .responses
        case .gemini, .openrouter, .ollama: .chatCompletions
        }
    }

    var baseURL: URL {
        switch self {
        case .anthropic: URL(string: "https://api.anthropic.com/v1/")!
        case .openai: URL(string: "https://api.openai.com/v1/")!
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/")!
        case .openrouter: URL(string: "https://openrouter.ai/api/v1/")!
        case .ollama: URL(string: "http://localhost:11434/v1/")!
        }
    }

    public var endpoint: URL {
        switch wire {
        case .anthropic: baseURL.appending(path: "messages")
        case .responses: baseURL.appending(path: "responses")
        case .chatCompletions: baseURL.appending(path: "chat/completions")
        }
    }

    public var modelsEndpoint: URL { baseURL.appending(path: "models") }

    public var needsKey: Bool { self != .ollama }

    public var keyAccount: String { "\(rawValue)-api-key" }

    public var keyPlaceholder: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openai: "sk-…"
        case .gemini: "AIza…"
        case .openrouter: "sk-or-…"
        case .ollama: ""
        }
    }

    public var keyPage: URL {
        switch self {
        case .anthropic: URL(string: "https://platform.claude.com")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        case .openrouter: URL(string: "https://openrouter.ai/settings/keys")!
        case .ollama: URL(string: "https://ollama.com/download")!
        }
    }

    public var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5-5"
        case .openai: "gpt-6.2-sol"
        case .gemini: "gemini-4-hydrogen"
        case .openrouter: "openrouter/auto"
        case .ollama: "qwen3"
        }
    }

    public var suggestedModels: [String] {
        switch self {
        case .anthropic: ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
        case .openai: ["gpt-6.2-astra", "gpt-6.2-sol", "gpt-6-luna"]
        case .gemini: ["gemini-4-carbon", "gemini-4-hydrogen", "gemini-3.5-flash-lite"]
        case .openrouter: ["openrouter/auto"]
        case .ollama: ["qwen3"]
        }
    }

    public var sendsEffort: Bool {
        switch self {
        case .anthropic, .openai, .gemini: true
        case .openrouter, .ollama: false
        }
    }

    public static func detect(key: String) -> Provider? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.hasPrefix("sk-ant-") { return .anthropic }
        if k.hasPrefix("sk-or-") { return .openrouter }
        if k.hasPrefix("AIza") { return .gemini }
        if k.hasPrefix("sk-") { return .openai }
        return nil
    }
}

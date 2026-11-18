public enum ChatError: Error, Equatable, Sendable {
    case missingKey, invalidKey, insufficientCredit, rateLimited, overloaded, network, refusal, incomplete
    case unknownModel, localServerDown
    case api(status: Int, message: String)

    public var userMessage: String {
        switch self {
        case .missingKey: "I need an API key. Open Settings."
        case .invalidKey: "That API key doesn't work. Check it in Settings."
        case .insufficientCredit: "Your API balance has run out. Top it up with your provider."
        case .rateLimited, .overloaded: "My brain is overloaded, try again in a minute."
        case .network: "I can't reach my brain. Check your internet."
        case .refusal: "I won't talk about that."
        case .incomplete: "I lost my train of thought. Please say that again."
        case .unknownModel: "That model isn't available. Pick another one in Settings."
        case .localServerDown: "I can't reach Ollama. Is it running?"
        case .api(let status, _): "Something broke (code \(status))."
        }
    }

    public var meansBadKey: Bool {
        self == .invalidKey || self == .missingKey
    }

    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded: true
        case .api(let status, _): status >= 500
        default: false
        }
    }

    public static func from(status: Int, body: String) -> ChatError {
        let message = (try? JSONValue.parse(body))?["error"]?["message"]?.stringValue ?? body
        switch status {
        case 401: return .invalidKey
        case 429: return .rateLimited
        case 529: return .overloaded
        case 400, 402, 403:
            return message.lowercased().contains("credit balance") ? .insufficientCredit : .api(status: status, message: message)
        default: return .api(status: status, message: message)
        }
    }

    static func fromStream(type: String, message: String) -> ChatError {
        switch type {
        case "overloaded_error": .overloaded
        case "rate_limit_error": .rateLimited
        case "authentication_error": .invalidKey
        default: .api(status: 0, message: message)
        }
    }

    public static func fromOpenAI(status: Int, body: String) -> ChatError {
        let parsed = try? JSONValue.parse(body)
        let error = parsed?["error"] ?? parsed?.arrayValue?.first?["error"]
        let message = error?["message"]?.stringValue ?? body
        let lower = message.lowercased()
        let code = [error?["code"]?.stringValue, error?["type"]?.stringValue, error?["status"]?.stringValue]
            .compactMap { $0?.lowercased() }.joined(separator: " ")
        if code.contains("insufficient_quota") { return .insufficientCredit }
        if code.contains("model_not_found") { return .unknownModel }
        switch status {
        case 401: return .invalidKey
        case 402: return .insufficientCredit
        case 429: return .rateLimited
        case 503, 529: return .overloaded
        case 404 where lower.contains("model"): return .unknownModel
        case 400 where lower.contains("api key"), 403 where lower.contains("api key"): return .invalidKey
        default: return .api(status: status, message: message)
        }
    }

    static func fromOpenAIStream(_ error: JSONValue?) -> ChatError {
        let message = error?["message"]?.stringValue ?? ""
        let code = [error?["code"]?.stringValue, error?["type"]?.stringValue]
            .compactMap { $0?.lowercased() }.joined(separator: " ")
        if code.contains("insufficient_quota") { return .insufficientCredit }
        if code.contains("rate_limit") { return .rateLimited }
        if code.contains("overloaded") || code.contains("server_error") { return .overloaded }
        if code.contains("model_not_found") { return .unknownModel }
        return .api(status: 0, message: message)
    }
}

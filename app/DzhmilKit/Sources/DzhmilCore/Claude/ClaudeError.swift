public enum ClaudeError: Error, Equatable, Sendable {
    case missingKey, invalidKey, insufficientCredit, rateLimited, overloaded, network, refusal, incomplete
    case api(status: Int, message: String)

    public var userMessage: String {
        switch self {
        case .missingKey: "I need an API key. Open Settings."
        case .invalidKey: "That API key doesn't work. Check it in Settings."
        case .insufficientCredit: "Your Claude balance has run out. Top it up in the Console."
        case .rateLimited, .overloaded: "My brain is overloaded, try again in a minute."
        case .network: "I can't reach my brain. Check your internet."
        case .refusal: "I won't talk about that."
        case .incomplete: "I lost my train of thought. Please say that again."
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

    public static func from(status: Int, body: String) -> ClaudeError {
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

    static func fromStream(type: String, message: String) -> ClaudeError {
        switch type {
        case "overloaded_error": .overloaded
        case "rate_limit_error": .rateLimited
        case "authentication_error": .invalidKey
        default: .api(status: 0, message: message)
        }
    }
}

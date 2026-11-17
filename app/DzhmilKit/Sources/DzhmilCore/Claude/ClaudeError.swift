public enum ClaudeError: Error, Equatable, Sendable {
    case missingKey, invalidKey, insufficientCredit, rateLimited, overloaded, network, refusal, incomplete
    case api(status: Int, message: String)

    public var userMessage: String {
        switch self {
        case .missingKey: "Мне нужен ключ API. Открой настройки."
        case .invalidKey: "Ключ API не подходит. Проверь его в настройках."
        case .insufficientCredit: "На балансе Claude закончились деньги. Пополни его в Console."
        case .rateLimited, .overloaded: "Мозг перегружен, попробуй через минуту."
        case .network: "Не могу связаться с мозгом, проверь интернет."
        case .refusal: "Об этом я говорить не буду."
        case .incomplete: "Я сбился на полуслове. Повтори, пожалуйста."
        case .api(let status, _): "Что-то сломалось (код \(status))."
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

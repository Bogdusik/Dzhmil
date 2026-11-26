public enum ChatError: Error, Equatable, Sendable {
    case missingKey, invalidKey, insufficientCredit, rateLimited, overloaded, network, refusal, incomplete
    case unknownModel, localServerDown, keyBlocked
    case api(status: Int, message: String)

    public var userMessage: String { userMessage(in: .english) }

    public func userMessage(in language: Language) -> String {
        switch self {
        case .missingKey: language.pick("I need an API key. Open Settings.", "Мне нужен API-ключ. Открой настройки.")
        case .invalidKey: language.pick("That API key doesn't work. Check it in Settings.", "Этот API-ключ не работает. Проверь его в настройках.")
        case .insufficientCredit: language.pick("Your API balance has run out. Top it up with your provider.", "На балансе API закончились деньги. Пополни его у провайдера.")
        case .rateLimited, .overloaded: language.pick("My brain is overloaded, try again in a minute.", "Мой мозг перегружен, попробуй через минуту.")
        case .network: language.pick("I can't reach my brain. Check your internet.", "Не могу достучаться до мозга. Проверь интернет.")
        case .refusal: language.pick("I won't talk about that.", "Об этом я говорить не буду.")
        case .incomplete: language.pick("I lost my train of thought. Please say that again.", "Я потерял мысль. Повтори, пожалуйста.")
        case .unknownModel: language.pick("That model isn't available. Pick another one in Settings.", "Эта модель недоступна. Выбери другую в настройках.")
        case .keyBlocked: language.pick("macOS didn't let me read my saved key. Quit me, open me again and click Always Allow.",
                                         "macOS не дала мне прочитать сохранённый ключ. Закрой меня, открой снова и нажми «Разрешать всегда» (Always Allow).")
        case .localServerDown: language.pick("I can't reach Ollama. Is it running?", "Не могу достучаться до Ollama. Она запущена?")
        case .api(let status, _): language.pick("Something broke (code \(status)).", "Что-то сломалось (код \(status)).")
        }
    }

    public var meansBadKey: Bool {
        self == .invalidKey || self == .missingKey
    }

    public var meansForgetKey: Bool {
        self == .invalidKey
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

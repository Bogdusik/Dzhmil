import Foundation

public struct OpenAIClient: ChatClient {
    private let provider: Provider
    private let apiKey: @Sendable () throws -> String?
    private let session: URLSession

    public init(provider: Provider, apiKey: @escaping @Sendable () throws -> String?, session: URLSession = .shared) {
        self.provider = provider
        self.apiKey = apiKey
        self.session = session
    }

    public func stream(_ request: MessagesRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        let make: @Sendable () throws -> URLRequest = { [provider, apiKey] in
            let body = switch provider.wire {
            case .responses: try ResponsesWire.body(request)
            default: try ChatCompletionsWire.body(request)
            }
            var r = try Self.authorized(URLRequest(url: provider.endpoint), provider: provider, key: try apiKey())
            r.httpMethod = "POST"
            r.httpBody = body
            r.timeoutInterval = 120
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            return r
        }
        return switch provider.wire {
        case .responses: HTTPStream.stream(session: session, decoder: ResponsesDecoder(), errorFrom: ChatError.fromOpenAI, request: make)
        default: HTTPStream.stream(session: session, decoder: ChatCompletionsDecoder(), errorFrom: ChatError.fromOpenAI, request: make)
        }
    }

    static func authorized(_ request: URLRequest, provider: Provider, key: String?) throws -> URLRequest {
        var r = request
        if provider.needsKey {
            guard let key, !key.isEmpty else { throw ChatError.missingKey }
            r.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        }
        if provider == .openrouter {
            r.setValue("https://github.com/Bogdusik/Dzhmil", forHTTPHeaderField: "http-referer")
            r.setValue("Dzhmil", forHTTPHeaderField: "x-title")
        }
        return r
    }
}

public enum ModelCatalog {
    static let skipped = ["embedding", "tts", "whisper", "dall-e", "image", "audio", "realtime", "transcribe", "moderation", "search", "codex"]

    public static func fetch(_ provider: Provider, key: String?, session: URLSession = .shared) async throws -> [String] {
        guard provider.wire != .anthropic else { return provider.suggestedModels }
        var request = try OpenAIClient.authorized(URLRequest(url: provider.modelsEndpoint), provider: provider, key: key)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(decoding: data, as: UTF8.self)
        guard status == 200 else { throw ChatError.fromOpenAI(status: status, body: body) }
        return ids(in: body)
    }

    static func ids(in body: String) -> [String] {
        let entries = (try? JSONValue.parse(body))?["data"]?.arrayValue ?? []
        let ids = entries.compactMap { $0["id"]?.stringValue }.map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
        return Array(Set(ids.filter { id in !skipped.contains { id.lowercased().contains($0) } })).sorted()
    }
}

import Foundation

public struct AnthropicClient: ChatClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private let apiKey: @Sendable () throws -> String?
    private let session: URLSession

    public init(apiKey: @escaping @Sendable () throws -> String?, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func stream(_ request: MessagesRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        HTTPStream.stream(session: session, decoder: StreamAccumulator(), errorFrom: ChatError.from) { [apiKey] in
            guard let key = try apiKey(), !key.isEmpty else { throw ChatError.missingKey }
            var urlRequest = URLRequest(url: Self.endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.httpBody = try request.body()
            urlRequest.timeoutInterval = 120
            for (k, v) in request.headers(apiKey: key) { urlRequest.setValue(v, forHTTPHeaderField: k) }
            return urlRequest
        }
    }
}

import Foundation

public enum StreamEvent: Sendable {
    case textDelta(String)
    case message(AssistantMessage)
}

public protocol ChatClient: Sendable {
    func stream(_ request: MessagesRequest) -> AsyncThrowingStream<StreamEvent, Error>
}

public protocol StreamDecoder: Sendable {
    mutating func consume(_ event: SSEEvent) throws -> String?
    func finish() throws -> AssistantMessage
}

enum HTTPStream {
    static let retryDelays: [Duration] = [.seconds(1), .seconds(3)]

    static func stream<D: StreamDecoder>(session: URLSession, decoder: D,
                                         errorFrom: @escaping @Sendable (Int, String) -> ChatError,
                                         request: @escaping @Sendable () throws -> URLRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try request()
                    let bytes = try await open(urlRequest, session: session, errorFrom: errorFrom)
                    try await read(bytes, decoder: decoder, continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let e as ChatError {
                    continuation.finish(throwing: e)
                } catch let e as URLError where e.code == .cancelled {
                    continuation.finish(throwing: CancellationError())
                } catch let e as URLError where e.code == .cannotConnectToHost && e.failingURL?.host() == "localhost" {
                    continuation.finish(throwing: ChatError.localServerDown)
                } catch is URLError {
                    continuation.finish(throwing: ChatError.network)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func read<D: StreamDecoder>(_ bytes: URLSession.AsyncBytes, decoder: D,
                                               _ continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws {
        var decoder = decoder
        var parser = SSEParser()
        var line = Data()

        func handle(_ events: [SSEEvent]) throws {
            for e in events {
                if let delta = try decoder.consume(e) { continuation.yield(.textDelta(delta)) }
            }
        }

        for try await byte in bytes {
            line.append(byte)
            if byte == UInt8(ascii: "\n") {
                try handle(parser.feed(String(decoding: line, as: UTF8.self)))
                line.removeAll(keepingCapacity: true)
            }
        }
        if !line.isEmpty { try handle(parser.feed(String(decoding: line, as: UTF8.self))) }
        try handle(parser.finish())
        continuation.yield(.message(try decoder.finish()))
    }

    private static func open(_ request: URLRequest, session: URLSession,
                             errorFrom: @Sendable (Int, String) -> ChatError) async throws -> URLSession.AsyncBytes {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return bytes }
            var body = Data()
            for try await b in bytes { body.append(b) }
            let error = errorFrom(status, String(decoding: body, as: UTF8.self))
            guard error.isRetryable, attempt < retryDelays.count else { throw error }
            try await Task.sleep(for: retryDelays[attempt])
            attempt += 1
        }
    }
}

public struct RoutingClient: ChatClient {
    private let apiKey: @Sendable (Provider) throws -> String?
    private let session: URLSession

    public init(apiKey: @escaping @Sendable (Provider) throws -> String?, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func stream(_ request: MessagesRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        let provider = request.provider
        let key: @Sendable () throws -> String? = { [apiKey] in try apiKey(provider) }
        return switch provider.wire {
        case .anthropic: AnthropicClient(apiKey: key, session: session).stream(request)
        case .responses, .chatCompletions: OpenAIClient(provider: provider, apiKey: key, session: session).stream(request)
        }
    }
}

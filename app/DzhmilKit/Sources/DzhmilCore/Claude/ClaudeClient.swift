import Foundation

public enum StreamEvent: Sendable {
    case textDelta(String)
    case message(AssistantMessage)
}

public protocol ClaudeClient: Sendable {
    func stream(_ request: MessagesRequest) -> AsyncThrowingStream<StreamEvent, Error>
}

public struct URLSessionClaudeClient: ClaudeClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let retryDelays: [Duration] = [.seconds(1), .seconds(3)]

    private let apiKey: @Sendable () -> String?
    private let session: URLSession

    public init(apiKey: @escaping @Sendable () -> String?, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func stream(_ request: MessagesRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let e as ClaudeError {
                    continuation.finish(throwing: e)
                } catch let e as URLError where e.code == .cancelled {
                    continuation.finish(throwing: CancellationError())
                } catch is URLError {
                    continuation.finish(throwing: ClaudeError.network)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ request: MessagesRequest, _ continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws {
        guard let key = apiKey(), !key.isEmpty else { throw ClaudeError.missingKey }
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try request.body()
        urlRequest.timeoutInterval = 120
        for (k, v) in request.headers(apiKey: key) { urlRequest.setValue(v, forHTTPHeaderField: k) }

        let bytes = try await open(urlRequest)
        var parser = SSEParser()
        var accumulator = StreamAccumulator()
        var line = Data()

        func handle(_ events: [SSEEvent]) throws {
            for e in events {
                if let delta = try accumulator.consume(e) { continuation.yield(.textDelta(delta)) }
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
        continuation.yield(.message(try accumulator.finish()))
    }

    private func open(_ request: URLRequest) async throws -> URLSession.AsyncBytes {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return bytes }
            var body = Data()
            for try await b in bytes { body.append(b) }
            let error = ClaudeError.from(status: status, body: String(decoding: body, as: UTF8.self))
            guard error.isRetryable, attempt < Self.retryDelays.count else { throw error }
            try await Task.sleep(for: Self.retryDelays[attempt])
            attempt += 1
        }
    }
}

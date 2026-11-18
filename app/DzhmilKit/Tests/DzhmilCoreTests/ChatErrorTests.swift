import Foundation
import Testing
@testable import DzhmilCore

@Suite struct ChatErrorTests {
    @Test func statusMapping() {
        #expect(ChatError.from(status: 401, body: "") == .invalidKey)
        #expect(ChatError.from(status: 400, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API."}}"#) == .insufficientCredit)
        #expect(ChatError.from(status: 429, body: "") == .rateLimited)
        #expect(ChatError.from(status: 529, body: "") == .overloaded)
        #expect(ChatError.from(status: 500, body: #"{"type":"error","error":{"type":"api_error","message":"boom"}}"#) == .api(status: 500, message: "boom"))
    }

    @Test func otherBadRequestsAreNotCredit() {
        #expect(ChatError.from(status: 400, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"image exceeds 5 MB maximum"}}"#)
                == .api(status: 400, message: "image exceeds 5 MB maximum"))
        #expect(ChatError.from(status: 402, body: "payment required") == .api(status: 402, message: "payment required"))
        #expect(ChatError.from(status: 403, body: #"{"error":{"message":"Your credit balance is too low"}}"#) == .insufficientCredit)
    }

    @Test func onlyKeyErrorsMeanBadKey() {
        #expect(ChatError.invalidKey.meansBadKey)
        #expect(ChatError.missingKey.meansBadKey)
        for error: ChatError in [.network, .overloaded, .rateLimited, .insufficientCredit, .api(status: 500, message: "")] {
            #expect(!error.meansBadKey)
        }
    }

    @Test func openAIStatusMapping() {
        #expect(ChatError.fromOpenAI(status: 401, body: #"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error","code":"invalid_api_key"}}"#) == .invalidKey)
        #expect(ChatError.fromOpenAI(status: 429, body: #"{"error":{"message":"You exceeded your current quota","type":"insufficient_quota","code":"insufficient_quota"}}"#) == .insufficientCredit)
        #expect(ChatError.fromOpenAI(status: 429, body: #"{"error":{"message":"Rate limit reached","type":"requests","code":"rate_limit_exceeded"}}"#) == .rateLimited)
        #expect(ChatError.fromOpenAI(status: 402, body: #"{"error":{"message":"Insufficient credits","code":402}}"#) == .insufficientCredit)
        #expect(ChatError.fromOpenAI(status: 404, body: #"{"error":{"message":"The model `gpt-x` does not exist","code":"model_not_found"}}"#) == .unknownModel)
        #expect(ChatError.fromOpenAI(status: 404, body: #"{"error":{"message":"model \"qwen9\" not found, try pulling it first"}}"#) == .unknownModel)
        #expect(ChatError.fromOpenAI(status: 400, body: #"[{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}]"#) == .invalidKey)
        #expect(ChatError.fromOpenAI(status: 400, body: #"{"error":{"message":"Invalid value for 'tools'"}}"#) == .api(status: 400, message: "Invalid value for 'tools'"))
        #expect(ChatError.fromOpenAI(status: 503, body: "") == .overloaded)
        #expect(ChatError.fromOpenAI(status: 500, body: "boom").isRetryable)
    }

    @Test func userMessages() {
        #expect(ChatError.missingKey.userMessage == "I need an API key. Open Settings.")
        #expect(ChatError.invalidKey.userMessage == "That API key doesn't work. Check it in Settings.")
        #expect(ChatError.insufficientCredit.userMessage == "Your API balance has run out. Top it up with your provider.")
        #expect(ChatError.rateLimited.userMessage == "My brain is overloaded, try again in a minute.")
        #expect(ChatError.overloaded.userMessage == "My brain is overloaded, try again in a minute.")
        #expect(ChatError.network.userMessage == "I can't reach my brain. Check your internet.")
        #expect(ChatError.refusal.userMessage == "I won't talk about that.")
        #expect(ChatError.api(status: 500, message: "x").userMessage == "Something broke (code 500).")
    }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var requests = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: JSONValue?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        Self.lastRequest = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            Self.lastBody = try? JSONDecoder().decode(JSONValue.self, from: data)
        }
        let r = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["content-type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: c)
    }
}

@Suite(.serialized) struct HTTPClientTests {
    let request = MessagesRequest(model: "claude-haiku-5-5", system: "S", messages: [["role": "user", "content": "hi"]], tools: [], effort: "low")

    func collect(_ client: AnthropicClient) async throws -> [StreamEvent] {
        var out: [StreamEvent] = []
        for try await e in client.stream(request) { out.append(e) }
        return out
    }

    @Test func missingKeyFailsWithoutRequest() async {
        StubProtocol.requests = 0
        let client = AnthropicClient(apiKey: { nil }, session: StubProtocol.session())
        await #expect(throws: ChatError.missingKey) { try await collect(client) }
        #expect(StubProtocol.requests == 0)
    }

    @Test func unauthorizedMapsToInvalidKey() async {
        StubProtocol.status = 401
        StubProtocol.body = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        let client = AnthropicClient(apiKey: { "bad" }, session: StubProtocol.session())
        await #expect(throws: ChatError.invalidKey) { try await collect(client) }
    }

    @Test func streamsTextAndFinalMessage() async throws {
        StubProtocol.status = 200
        StubProtocol.body = Data("""
        event: message_start
        data: {"type":"message_start","message":{"id":"m","type":"message","role":"assistant","content":[]}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

        event: message_stop
        data: {"type":"message_stop"}


        """.utf8)
        let client = AnthropicClient(apiKey: { "k" }, session: StubProtocol.session())
        let events = try await collect(client)
        guard events.count == 2, case .textDelta(let t) = events[0], case .message(let m) = events[1] else {
            Issue.record("unexpected events \(events)")
            return
        }
        #expect(t == "Hello")
        #expect(m.text == "Hello")
    }

    func collect(_ client: some ChatClient, _ request: MessagesRequest) async throws -> [StreamEvent] {
        var out: [StreamEvent] = []
        for try await e in client.stream(request) { out.append(e) }
        return out
    }

    @Test func openAIUsesResponsesWithBearerKey() async throws {
        StubProtocol.status = 200
        StubProtocol.body = Data("""
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"Hi"}

        event: response.completed
        data: {"type":"response.completed","response":{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Hi"}]}]}}


        """.utf8)
        let client = RoutingClient(apiKey: { $0 == .openai ? "sk-test" : nil }, session: StubProtocol.session())
        let r = MessagesRequest(model: "gpt-6.2-sol", system: "S", messages: [["role": "user", "content": "hi"]], tools: [], effort: "low", provider: .openai)
        let events = try await collect(client, r)
        #expect(StubProtocol.lastRequest?.url == Provider.openai.endpoint)
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "authorization") == "Bearer sk-test")
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "x-api-key") == nil)
        #expect(StubProtocol.lastBody?["instructions"] == "S")
        guard events.count == 2, case .textDelta("Hi") = events[0], case .message(let m) = events[1] else {
            Issue.record("unexpected events \(events)")
            return
        }
        #expect(m.text == "Hi")
    }

    @Test func ollamaNeedsNoKey() async throws {
        StubProtocol.status = 200
        StubProtocol.body = Data("""
        data: {"choices":[{"delta":{"content":"Hey"},"finish_reason":"stop"}]}

        data: [DONE]


        """.utf8)
        let client = RoutingClient(apiKey: { _ in nil }, session: StubProtocol.session())
        let r = MessagesRequest(model: "qwen3", system: "S", messages: [["role": "user", "content": "hi"]], tools: [], effort: "low", provider: .ollama)
        let events = try await collect(client, r)
        #expect(StubProtocol.lastRequest?.url == Provider.ollama.endpoint)
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "authorization") == nil)
        #expect(events.count == 2)
    }

    @Test func otherProvidersNeedTheirOwnKey() async {
        StubProtocol.requests = 0
        let client = RoutingClient(apiKey: { $0 == .anthropic ? "sk-ant" : nil }, session: StubProtocol.session())
        let r = MessagesRequest(model: "gemini-4-hydrogen", system: "S", messages: [], tools: [], effort: "low", provider: .gemini)
        await #expect(throws: ChatError.missingKey) { try await collect(client, r) }
        #expect(StubProtocol.requests == 0)
    }

    @Test func openAIErrorsAreMapped() async {
        StubProtocol.status = 401
        StubProtocol.body = Data(#"{"error":{"message":"Incorrect API key provided","code":"invalid_api_key"}}"#.utf8)
        let client = RoutingClient(apiKey: { _ in "bad" }, session: StubProtocol.session())
        let r = MessagesRequest(model: "m", system: "S", messages: [], tools: [], effort: "low", provider: .openrouter)
        await #expect(throws: ChatError.invalidKey) { try await collect(client, r) }
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "x-title") == "Dzhmil")
    }
}

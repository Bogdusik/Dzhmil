import Foundation
import Testing
@testable import DzhmilCore

@Suite struct ClaudeErrorTests {
    @Test func statusMapping() {
        #expect(ClaudeError.from(status: 401, body: "") == .invalidKey)
        #expect(ClaudeError.from(status: 400, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API."}}"#) == .insufficientCredit)
        #expect(ClaudeError.from(status: 429, body: "") == .rateLimited)
        #expect(ClaudeError.from(status: 529, body: "") == .overloaded)
        #expect(ClaudeError.from(status: 500, body: #"{"type":"error","error":{"type":"api_error","message":"boom"}}"#) == .api(status: 500, message: "boom"))
    }

    @Test func otherBadRequestsAreNotCredit() {
        #expect(ClaudeError.from(status: 400, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"image exceeds 5 MB maximum"}}"#)
                == .api(status: 400, message: "image exceeds 5 MB maximum"))
        #expect(ClaudeError.from(status: 402, body: "payment required") == .api(status: 402, message: "payment required"))
        #expect(ClaudeError.from(status: 403, body: #"{"error":{"message":"Your credit balance is too low"}}"#) == .insufficientCredit)
    }

    @Test func onlyKeyErrorsMeanBadKey() {
        #expect(ClaudeError.invalidKey.meansBadKey)
        #expect(ClaudeError.missingKey.meansBadKey)
        for error: ClaudeError in [.network, .overloaded, .rateLimited, .insufficientCredit, .api(status: 500, message: "")] {
            #expect(!error.meansBadKey)
        }
    }

    @Test func userMessages() {
        #expect(ClaudeError.missingKey.userMessage == "I need an API key. Open Settings.")
        #expect(ClaudeError.invalidKey.userMessage == "That API key doesn't work. Check it in Settings.")
        #expect(ClaudeError.insufficientCredit.userMessage == "Your Claude balance has run out. Top it up in the Console.")
        #expect(ClaudeError.rateLimited.userMessage == "My brain is overloaded, try again in a minute.")
        #expect(ClaudeError.overloaded.userMessage == "My brain is overloaded, try again in a minute.")
        #expect(ClaudeError.network.userMessage == "I can't reach my brain. Check your internet.")
        #expect(ClaudeError.refusal.userMessage == "I won't talk about that.")
        #expect(ClaudeError.api(status: 500, message: "x").userMessage == "Something broke (code 500).")
    }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
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

@Suite(.serialized) struct URLSessionClaudeClientTests {
    let request = MessagesRequest(model: "claude-haiku-5-5", system: "S", messages: [["role": "user", "content": "hi"]], tools: [], effort: "low")

    func collect(_ client: URLSessionClaudeClient) async throws -> [StreamEvent] {
        var out: [StreamEvent] = []
        for try await e in client.stream(request) { out.append(e) }
        return out
    }

    @Test func missingKeyFailsWithoutRequest() async {
        StubProtocol.requests = 0
        let client = URLSessionClaudeClient(apiKey: { nil }, session: StubProtocol.session())
        await #expect(throws: ClaudeError.missingKey) { try await collect(client) }
        #expect(StubProtocol.requests == 0)
    }

    @Test func unauthorizedMapsToInvalidKey() async {
        StubProtocol.status = 401
        StubProtocol.body = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        let client = URLSessionClaudeClient(apiKey: { "bad" }, session: StubProtocol.session())
        await #expect(throws: ClaudeError.invalidKey) { try await collect(client) }
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
        let client = URLSessionClaudeClient(apiKey: { "k" }, session: StubProtocol.session())
        let events = try await collect(client)
        guard events.count == 2, case .textDelta(let t) = events[0], case .message(let m) = events[1] else {
            Issue.record("unexpected events \(events)")
            return
        }
        #expect(t == "Hello")
        #expect(m.text == "Hello")
    }
}

import Testing
@testable import DzhmilCore

@Suite struct SSEParserTests {
    @Test func eventSplitAcrossFeeds() {
        var p = SSEParser()
        #expect(p.feed("event: message_start\ndata: {\"a\"").isEmpty)
        #expect(p.feed(":1}\n\n") == [SSEEvent(event: "message_start", data: #"{"a":1}"#)])
    }

    @Test func twoEventsInOneChunk() {
        var p = SSEParser()
        let out = p.feed("event: a\ndata: 1\n\nevent: b\ndata: 2\n\n")
        #expect(out == [SSEEvent(event: "a", data: "1"), SSEEvent(event: "b", data: "2")])
    }

    @Test func crlfLineEndings() {
        var p = SSEParser()
        #expect(p.feed("event: a\r\ndata: x\r\n\r\n") == [SSEEvent(event: "a", data: "x")])
    }

    @Test func commentsIgnored() {
        var p = SSEParser()
        #expect(p.feed(": keepalive\n\n").isEmpty)
        #expect(p.feed(": hi\nevent: a\ndata: 1\n\n") == [SSEEvent(event: "a", data: "1")])
    }

    @Test func pingPassesThrough() {
        var p = SSEParser()
        #expect(p.feed("event: ping\ndata: {\"type\": \"ping\"}\n\n") == [SSEEvent(event: "ping", data: #"{"type": "ping"}"#)])
    }

    @Test func multilineDataJoined() {
        var p = SSEParser()
        #expect(p.feed("data: a\ndata: b\n\n") == [SSEEvent(event: nil, data: "a\nb")])
    }

    @Test func finishFlushesPendingEvent() {
        var p = SSEParser()
        #expect(p.feed("event: a\ndata: 1\n").isEmpty)
        #expect(p.finish() == [SSEEvent(event: "a", data: "1")])
    }
}

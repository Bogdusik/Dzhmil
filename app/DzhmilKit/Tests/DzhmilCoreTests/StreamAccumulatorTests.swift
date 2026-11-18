import Testing
@testable import DzhmilCore

@Suite struct StreamAccumulatorTests {
    let start = SSEEvent(event: "message_start", data: #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-opus-5-5","stop_reason":null}}"#)
    let stop = SSEEvent(event: "message_stop", data: #"{"type":"message_stop"}"#)

    func ev(_ name: String, _ data: String) -> SSEEvent { SSEEvent(event: name, data: data) }
    func blockStart(_ i: Int, _ block: String) -> SSEEvent { ev("content_block_start", #"{"type":"content_block_start","index":\#(i),"content_block":\#(block)}"#) }
    func delta(_ i: Int, _ d: String) -> SSEEvent { ev("content_block_delta", #"{"type":"content_block_delta","index":\#(i),"delta":\#(d)}"#) }
    func blockStop(_ i: Int) -> SSEEvent { ev("content_block_stop", #"{"type":"content_block_stop","index":\#(i)}"#) }
    func messageDelta(_ reason: String) -> SSEEvent { ev("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"\#(reason)"},"usage":{"output_tokens":3}}"#) }

    @Test func textDeltasAccumulate() throws {
        var a = StreamAccumulator()
        var deltas: [String] = []
        for e in [start, blockStart(0, #"{"type":"text","text":""}"#),
                  delta(0, #"{"type":"text_delta","text":"Hel"}"#),
                  delta(0, #"{"type":"text_delta","text":"lo"}"#),
                  blockStop(0), messageDelta("end_turn"), stop] {
            if let d = try a.consume(e) { deltas.append(d) }
        }
        #expect(deltas == ["Hel", "lo"])
        let m = try a.finish()
        #expect(m.text == "Hello")
        #expect(m.stopReason == "end_turn")
        #expect(m.content == [["type": "text", "text": "Hello"]])
        #expect(m.asHistoryEntry == ["role": "assistant", "content": [["type": "text", "text": "Hello"]]])
    }

    @Test func thinkingAndToolUseAreKeptExactly() throws {
        var a = StreamAccumulator()
        for e in [start,
                  blockStart(0, #"{"type":"thinking","thinking":"","signature":""}"#),
                  delta(0, #"{"type":"thinking_delta","thinking":"hmm"}"#),
                  delta(0, #"{"type":"signature_delta","signature":"sig=="}"#),
                  blockStop(0),
                  blockStart(1, #"{"type":"tool_use","id":"toolu_1","name":"open_app","input":{}}"#),
                  delta(1, #"{"type":"input_json_delta","partial_json":"{\"ap"}"#),
                  delta(1, #"{"type":"input_json_delta","partial_json":"p\": \"Saf"}"#),
                  delta(1, #"{"type":"input_json_delta","partial_json":"ari\"}"}"#),
                  blockStop(1), messageDelta("tool_use"), stop] {
            _ = try a.consume(e)
        }
        let m = try a.finish()
        #expect(m.content[0] == ["type": "thinking", "thinking": "hmm", "signature": "sig=="])
        #expect(m.content[1] == ["type": "tool_use", "id": "toolu_1", "name": "open_app", "input": ["app": "Safari"]])
        #expect(m.toolUses == [ToolUse(id: "toolu_1", name: "open_app", input: ["app": "Safari"])])
        #expect(m.stopReason == "tool_use")
        #expect(m.text == "")
    }

    @Test func emptyToolInputBecomesEmptyObject() throws {
        var a = StreamAccumulator()
        for e in [start, blockStart(0, #"{"type":"tool_use","id":"t","name":"list_running_apps","input":{}}"#), blockStop(0), messageDelta("tool_use")] {
            _ = try a.consume(e)
        }
        #expect(try a.finish().toolUses.first?.input == .object([:]))
    }

    @Test func unknownBlocksAreKeptAsIs() throws {
        var a = StreamAccumulator()
        let fallback = #"{"type":"fallback","from":{"model":"claude-opus-5-5"},"to":{"model":"claude-opus-5"}}"#
        for e in [start, blockStart(0, fallback), blockStop(0),
                  blockStart(1, #"{"type":"text","text":""}"#), delta(1, #"{"type":"text_delta","text":"ok"}"#), blockStop(1),
                  messageDelta("end_turn")] {
            _ = try a.consume(e)
        }
        let m = try a.finish()
        #expect(m.content[0] == (try JSONValue.parse(fallback)))
        #expect(m.text == "ok")
    }

    @Test func refusalThrows() throws {
        var a = StreamAccumulator()
        for e in [start, messageDelta("refusal")] { _ = try a.consume(e) }
        #expect(throws: ChatError.refusal) { try a.finish() }
    }

    @Test func streamErrorThrows() {
        var a = StreamAccumulator()
        #expect(throws: ChatError.overloaded) {
            try a.consume(SSEEvent(event: "error", data: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#))
        }
    }

    @Test func streamWithoutStopReasonIsIncomplete() throws {
        var a = StreamAccumulator()
        for e in [start, blockStart(0, #"{"type":"text","text":""}"#), delta(0, #"{"type":"text_delta","text":"Hal"}"#)] {
            _ = try a.consume(e)
        }
        #expect(throws: ChatError.incomplete) { try a.finish() }
    }

    @Test func pingIsIgnored() throws {
        var a = StreamAccumulator()
        #expect(try a.consume(SSEEvent(event: "ping", data: #"{"type":"ping"}"#)) == nil)
    }
}

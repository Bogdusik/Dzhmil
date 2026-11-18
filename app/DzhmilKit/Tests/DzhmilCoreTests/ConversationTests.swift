import Foundation
import Testing
@testable import DzhmilCore

final class FakeChatClient: ChatClient, @unchecked Sendable {
    indirect enum Step: Sendable {
        case reply(deltas: [String], message: AssistantMessage)
        case fail(ChatError)
        case hang
        case after(Duration, Step)
    }

    private let lock = NSLock()
    private var steps: [Step]
    private var _requests: [MessagesRequest] = []

    init(_ steps: [Step]) { self.steps = steps }

    var requests: [MessagesRequest] { lock.withLock { _requests } }

    func stream(_ request: MessagesRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        let step: Step = lock.withLock {
            _requests.append(request)
            return steps.isEmpty ? .fail(.network) : steps.removeFirst()
        }
        return AsyncThrowingStream { cont in
            let task = Task { await Self.play(step, cont) }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    private static func play(_ step: Step, _ cont: AsyncThrowingStream<StreamEvent, Error>.Continuation) async {
        switch step {
        case .reply(let deltas, let message):
            for d in deltas { cont.yield(.textDelta(d)) }
            cont.yield(.message(message))
            cont.finish()
        case .fail(let e):
            cont.finish(throwing: e)
        case .hang:
            do {
                try await Task.sleep(for: .seconds(100))
                cont.finish()
            } catch {
                cont.finish(throwing: CancellationError())
            }
        case .after(let delay, let next):
            do {
                try await Task.sleep(for: delay)
                await play(next, cont)
            } catch {
                cont.finish(throwing: CancellationError())
            }
        }
    }
}

final class ProfileBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String
    init(_ v: String) { _value = v }
    var value: String {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ d: Date) { value = d }
    var now: Date { lock.withLock { value } }
    func advance(_ s: TimeInterval) { lock.withLock { value += s } }
}

enum Fixtures {
    static func text(_ t: String) -> FakeChatClient.Step {
        .reply(deltas: [t], message: AssistantMessage(content: [["type": "thinking", "thinking": "", "signature": "sig1"], ["type": "text", "text": .string(t)]], stopReason: "end_turn"))
    }

    static func toolCall(_ uses: [(String, String, JSONValue)], text: String = "") -> FakeChatClient.Step {
        var content: [JSONValue] = [["type": "thinking", "thinking": "", "signature": "sig2"]]
        if !text.isEmpty { content.append(["type": "text", "text": .string(text)]) }
        for (id, name, input) in uses { content.append(["type": "tool_use", "id": .string(id), "name": .string(name), "input": input]) }
        return .reply(deltas: text.isEmpty ? [] : [text], message: AssistantMessage(content: content, stopReason: "tool_use"))
    }
}

@Suite struct ConversationTests {
    let clock = TestClock(ISO8601DateFormatter().date(from: "2026-11-15T14:05:00Z")!)

    func make(_ steps: [FakeChatClient.Step], tools: [any Tool] = [RecordingTool(name: "open_app")], confirm: ScriptedConfirmer.Mode = .yes) -> (Conversation, FakeChatClient) {
        let client = FakeChatClient(steps)
        let executor = ToolExecutor(tools: tools, confirmer: ScriptedConfirmer(mode: confirm))
        let clock = self.clock
        let conv = Conversation(client: client, executor: executor,
                                settings: { ConversationSettings(model: "claude-opus-5-5", effort: "low") },
                                profile: { "My name is Alex." },
                                now: { clock.now },
                                timeZone: TimeZone(identifier: "Europe/London")!)
        return (conv, client)
    }

    func collect(_ stream: AsyncStream<ConversationEvent>) async -> [ConversationEvent] {
        var out: [ConversationEvent] = []
        for await e in stream { out.append(e) }
        return out
    }

    @Test func plainReply() async throws {
        let (conv, client) = make([Fixtures.text("Hi! All good.")])
        let events = await collect(await conv.send("hi"))
        #expect(events == [.sentence("Hi!"), .sentence("All good."), .finished(text: "Hi! All good.", didAct: false)])
        let history = await conv.history
        #expect(history.count == 2)
        #expect(history[0]["role"] == "user")
        #expect(history[0]["content"]?.stringValue?.hasSuffix("\nhi") == true)
        guard case .reply(_, let message) = Fixtures.text("Hi! All good.") else { return }
        #expect(try history[1].encodedData() == message.asHistoryEntry.encodedData())
        #expect(client.requests.first?.model == "claude-opus-5-5")
        #expect(client.requests.first?.effort == "low")
    }

    @Test func toolCallWrittenAsTextIsHiddenAndRetried() async {
        let junk = "Sure! <invoke name=\"mute\">\n<parameter name=\"muted\">false</parameter>\n</invoke>"
        let (conv, client) = make([Fixtures.text(junk), Fixtures.text("Unmuted.")])
        let events = await collect(await conv.send("unmute"))
        #expect(events == [.sentence("Sure!"), .sentence("Unmuted."), .finished(text: "Sure! Unmuted.", didAct: false)])
        #expect(client.requests.count == 2)
        let history = await conv.history
        #expect(history.count == 2)
        #expect(history[1]["content"]?.arrayValue?.last?["text"] == "Unmuted.")
    }

    @Test func toolCallWrittenAsTextTwiceGivesUp() async {
        let junk = "<invoke name=\"mute\">\n<parameter name=\"muted\">false</parameter>\n</invoke>"
        let (conv, client) = make([Fixtures.text(junk), Fixtures.text(junk)])
        let events = await collect(await conv.send("unmute"))
        #expect(events == [.sentence(Conversation.lostMessage), .finished(text: Conversation.lostMessage, didAct: false)])
        #expect(client.requests.count == 2)
        #expect(await conv.history.isEmpty)
    }

    @Test func emotionTagsBecomeEventsAndStayOutOfText() async {
        let raw = "<happy> Yay! All done."
        let message = AssistantMessage(content: [["type": "text", "text": .string(raw)]], stopReason: "end_turn")
        let (conv, _) = make([.reply(deltas: ["<hap", "py> Yay! All ", "done."], message: message)])
        let events = await collect(await conv.send("do it"))
        #expect(events == [.emotion(.happy), .sentence("Yay!"), .sentence("All done."), .finished(text: "Yay! All done.", didAct: false)])
        let history = await conv.history
        guard case .array(let blocks)? = history.last?["content"] else { Issue.record("no content"); return }
        #expect(blocks.first?["text"]?.stringValue == raw)
    }

    @Test func toolRoundTrip() async {
        let tool = RecordingTool(name: "open_app")
        let (conv, client) = make([Fixtures.toolCall([("toolu_1", "open_app", ["x": "Calculator"])]), Fixtures.text("Opened.")], tools: [tool])
        let events = await collect(await conv.send("open calculator"))
        #expect(events.contains(.toolStarted("open_app")))
        #expect(events.contains(.toolFinished("open_app", ran: true)))
        #expect(events.last == .finished(text: "Opened.", didAct: true))
        #expect(await tool.runs.value == 1)
        let history = await conv.history
        #expect(history.count == 4)
        let result = history[2]["content"]?.arrayValue?.first
        #expect(history[2]["role"] == "user")
        #expect(result?["type"] == "tool_result")
        #expect(result?["tool_use_id"] == "toolu_1")
        #expect(result?["content"] == "done")
        #expect(client.requests.count == 2)
    }

    @Test func imageToolResultBuildsBlocks() async {
        let (conv, _) = make([Fixtures.toolCall([("toolu_9", "look", [:])]), Fixtures.text("I see Safari.")], tools: [PictureTool()])
        _ = await collect(await conv.send("look"))
        let history = await conv.history
        let result = history[2]["content"]?.arrayValue?.first
        #expect(result?["tool_use_id"] == "toolu_9")
        #expect(result?["content"] == [
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": "AAAA"]],
            ["type": "text", "text": "Screenshot"],
        ])
    }

    @Test func parallelToolResultsInOneMessage() async {
        let (conv, _) = make([Fixtures.toolCall([("a", "open_app", ["x": "1"]), ("b", "open_app", ["x": "2"])]), Fixtures.text("Done.")])
        _ = await collect(await conv.send("open two"))
        let history = await conv.history
        #expect(history.count == 4)
        #expect(history[2]["content"]?.arrayValue?.count == 2)
        #expect(history[2]["content"]?.arrayValue?.map { $0["tool_use_id"] } == ["a", "b"])
    }

    @Test func deniedToolIsNotAnAct() async {
        let tool = RecordingTool(name: "quit_app", dangerous: true)
        let (conv, _) = make([Fixtures.toolCall([("t", "quit_app", ["x": "Safari"])]), Fixtures.text("OK, not quitting.")], tools: [tool], confirm: .no)
        let events = await collect(await conv.send("quit safari"))
        #expect(events.contains(.toolFinished("quit_app", ran: false)))
        #expect(events.last == .finished(text: "OK, not quitting.", didAct: false))
        #expect(await tool.runs.value == 0)
    }

    @Test func cancelBeforeAnyToolRollsBack() async throws {
        let (conv, client) = make([Fixtures.text("First reply."), .hang])
        _ = await collect(await conv.send("one"))
        let snapshot = await conv.history
        let stream = await conv.send("two")
        let collector = Task { await collect(stream) }
        for _ in 0..<200 where client.requests.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        await conv.cancel()
        let events = await collector.value
        #expect(!events.contains { if case .finished = $0 { true } else { false } })
        #expect(await conv.history == snapshot)
    }

    @Test func cancelKeepsToolsThatAlreadyRan() async throws {
        let (conv, client) = make([Fixtures.text("First reply."), Fixtures.toolCall([("t", "open_app", ["x": "1"])]), .hang])
        _ = await collect(await conv.send("one"))
        let before = await conv.history.count
        let stream = await conv.send("two")
        let collector = Task { await collect(stream) }
        for _ in 0..<200 where client.requests.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(client.requests.count == 3)
        await conv.cancel()
        _ = await collector.value
        let history = await conv.history
        #expect(history.count == before + 3)
        #expect(history.last?["content"]?.arrayValue?.first?["tool_use_id"] == "t")
    }

    @Test func failureAfterToolKeepsWhatRanAndMergesNextTurn() async throws {
        let (conv, client) = make([Fixtures.toolCall([("t", "open_app", ["x": "1"])]), .fail(.network), Fixtures.text("OK.")])
        let events = await collect(await conv.send("open"))
        #expect(events.last == .failed(.network))
        let history = await conv.history
        try #require(history.count == 3)
        #expect(history[2]["content"]?.arrayValue?.first?["type"] == "tool_result")
        _ = await collect(await conv.send("again"))
        try #require(client.requests.count == 3)
        let sent = client.requests[2].messages
        #expect(sent.count == 3)
        let blocks = sent.last?["content"]?.arrayValue ?? []
        #expect(blocks.first?["type"] == "tool_result")
        #expect(blocks.last?["type"] == "text")
        #expect(blocks.last?["text"]?.stringValue?.hasSuffix("\nagain") == true)
    }

    @Test func resetSessionLetsTheCurrentTurnFinish() async throws {
        let (conv, client) = make([.after(.milliseconds(200), Fixtures.text("Done.")), Fixtures.text("New.")])
        let stream = await conv.send("do it")
        let collector = Task { await collect(stream) }
        for _ in 0..<200 where client.requests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        await conv.resetSession()
        let events = await collector.value
        #expect(events.last == .finished(text: "Done.", didAct: false))
        _ = await collect(await conv.send("start over"))
        try #require(client.requests.count == 2)
        #expect(client.requests[1].messages.count == 1)
    }

    @Test func errorEmitsFailedAndRollsBack() async {
        let (conv, _) = make([.fail(.network)])
        let events = await collect(await conv.send("hi"))
        #expect(events == [.failed(.network)])
        #expect(await conv.history.isEmpty)
    }

    @Test func roundLimit() async {
        let steps = (0..<9).map { Fixtures.toolCall([("t\($0)", "open_app", ["x": "1"])]) }
        let (conv, client) = make(steps)
        let events = await collect(await conv.send("spin"))
        #expect(client.requests.count == 8)
        guard case .finished(let text, _) = events.last else {
            Issue.record("no finished event")
            return
        }
        #expect(text == "I got confused, let's try another way.")
    }

    @Test func remarkConsumedOnce() async {
        let (conv, client) = make([Fixtures.text("Good."), Fixtures.text("OK.")])
        await conv.noteRemark("How are you?")
        _ = await collect(await conv.send("fine"))
        _ = await collect(await conv.send("and you?"))
        let first = client.requests[0].messages.last?["content"]?.stringValue ?? ""
        let second = client.requests[1].messages.last?["content"]?.stringValue ?? ""
        #expect(first.contains("[Dzhmil just said: “How are you?”]"))
        #expect(!second.contains("Dzhmil just said"))
    }

    @Test func staleSessionResetsAfterSilence() async {
        let (conv, _) = make([Fixtures.text("Hi.")])
        _ = await collect(await conv.send("hi"))
        clock.advance(29 * 60)
        await conv.resetIfStale()
        #expect(await conv.history.count == 2)
        clock.advance(2 * 60)
        await conv.resetIfStale()
        #expect(await conv.history.isEmpty)
    }

    @Test func staleSessionResetsAfterSixtyMessages() async {
        let (conv, _) = make((0..<30).map { _ in Fixtures.text("OK.") })
        for _ in 0..<30 { _ = await collect(await conv.send("more")) }
        #expect(await conv.history.count == 60)
        await conv.resetIfStale()
        #expect(await conv.history.isEmpty)
    }

    @Test func emptyReplyAfterToolKeepsTheToolRound() async {
        let empty = FakeChatClient.Step.reply(deltas: [], message: AssistantMessage(content: [], stopReason: "end_turn"))
        let (conv, _) = make([Fixtures.toolCall([("t", "open_app", ["x": "1"])]), empty])
        let events = await collect(await conv.send("open"))
        #expect(events.last == .finished(text: "", didAct: true))
        #expect(await conv.history.count == 3)
    }

    @Test func truncatedToolUseFails() async {
        let truncated = FakeChatClient.Step.reply(deltas: [], message: AssistantMessage(content: [["type": "tool_use", "id": "t", "name": "open_app", "input": ["x": "1"]]], stopReason: "max_tokens"))
        let (conv, _) = make([truncated])
        let events = await collect(await conv.send("open"))
        #expect(events == [.failed(.incomplete)])
        #expect(await conv.history.isEmpty)
    }

    @Test func badRequestResetsSession() async {
        let (conv, _) = make([Fixtures.text("Hi."), .fail(.api(status: 400, message: "bad"))])
        _ = await collect(await conv.send("hi"))
        #expect(await conv.history.count == 2)
        let events = await collect(await conv.send("more"))
        #expect(events == [.failed(.api(status: 400, message: "bad"))])
        #expect(await conv.history.isEmpty)
    }

    @Test func systemIsFrozenWithinSession() async {
        let client = FakeChatClient([Fixtures.text("One."), Fixtures.text("Two."), Fixtures.text("Three.")])
        let profile = ProfileBox("Profile A")
        let conv = Conversation(client: client, executor: ToolExecutor(tools: [], confirmer: ScriptedConfirmer(mode: .yes)),
                                settings: { ConversationSettings(model: "claude-opus-5-5", effort: "low") },
                                profile: { profile.value })
        _ = await collect(await conv.send("one"))
        profile.value = "Profile B"
        _ = await collect(await conv.send("two"))
        #expect(client.requests[1].system == client.requests[0].system)
        await conv.resetSession()
        _ = await collect(await conv.send("three"))
        #expect(client.requests[2].system.contains("Profile B"))
    }

    @Test func systemAndToolsAreStableAcrossRounds() async throws {
        let (conv, client) = make([Fixtures.toolCall([("t", "open_app", ["x": "1"])]), Fixtures.text("Yes.")])
        _ = await collect(await conv.send("do it"))
        let reqs = client.requests
        #expect(reqs.count == 2)
        #expect(reqs[0].system == reqs[1].system)
        #expect(try JSONValue.array(reqs[0].tools).encodedData() == JSONValue.array(reqs[1].tools).encodedData())
        #expect(try JSONValue.array(Array(reqs[1].messages.prefix(1))).encodedData() == JSONValue.array(reqs[0].messages).encodedData())
    }
}

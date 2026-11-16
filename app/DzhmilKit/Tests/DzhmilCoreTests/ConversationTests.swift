import Foundation
import Testing
@testable import DzhmilCore

final class FakeClaudeClient: ClaudeClient, @unchecked Sendable {
    enum Step {
        case reply(deltas: [String], message: AssistantMessage)
        case fail(ClaudeError)
        case hang
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
            let task = Task {
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
                }
            }
            cont.onTermination = { _ in task.cancel() }
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
    static func text(_ t: String) -> FakeClaudeClient.Step {
        .reply(deltas: [t], message: AssistantMessage(content: [["type": "thinking", "thinking": "", "signature": "sig1"], ["type": "text", "text": .string(t)]], stopReason: "end_turn"))
    }

    static func toolCall(_ uses: [(String, String, JSONValue)], text: String = "") -> FakeClaudeClient.Step {
        var content: [JSONValue] = [["type": "thinking", "thinking": "", "signature": "sig2"]]
        if !text.isEmpty { content.append(["type": "text", "text": .string(text)]) }
        for (id, name, input) in uses { content.append(["type": "tool_use", "id": .string(id), "name": .string(name), "input": input]) }
        return .reply(deltas: text.isEmpty ? [] : [text], message: AssistantMessage(content: content, stopReason: "tool_use"))
    }
}

@Suite struct ConversationTests {
    let clock = TestClock(ISO8601DateFormatter().date(from: "2026-11-15T14:05:00Z")!)

    func make(_ steps: [FakeClaudeClient.Step], tools: [any Tool] = [RecordingTool(name: "open_app")], confirm: ScriptedConfirmer.Mode = .yes) -> (Conversation, FakeClaudeClient) {
        let client = FakeClaudeClient(steps)
        let executor = ToolExecutor(tools: tools, confirmer: ScriptedConfirmer(mode: confirm))
        let clock = self.clock
        let conv = Conversation(client: client, executor: executor,
                                settings: { ConversationSettings(model: "claude-opus-5-5", effort: "low") },
                                profile: { "Меня зовут Богдан." },
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
        let (conv, client) = make([Fixtures.text("Привет! Всё хорошо.")])
        let events = await collect(await conv.send("привет"))
        #expect(events == [.sentence("Привет!"), .sentence("Всё хорошо."), .finished(text: "Привет! Всё хорошо.", didAct: false)])
        let history = await conv.history
        #expect(history.count == 2)
        #expect(history[0]["role"] == "user")
        #expect(history[0]["content"]?.stringValue?.hasSuffix("\nпривет") == true)
        guard case .reply(_, let message) = Fixtures.text("Привет! Всё хорошо.") else { return }
        #expect(try history[1].encodedData() == message.asHistoryEntry.encodedData())
        #expect(client.requests.first?.model == "claude-opus-5-5")
        #expect(client.requests.first?.effort == "low")
    }

    @Test func toolRoundTrip() async {
        let tool = RecordingTool(name: "open_app")
        let (conv, client) = make([Fixtures.toolCall([("toolu_1", "open_app", ["x": "Calculator"])]), Fixtures.text("Открыл.")], tools: [tool])
        let events = await collect(await conv.send("открой калькулятор"))
        #expect(events.contains(.toolStarted("open_app")))
        #expect(events.contains(.toolFinished("open_app", ran: true)))
        #expect(events.last == .finished(text: "Открыл.", didAct: true))
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
        let (conv, _) = make([Fixtures.toolCall([("toolu_9", "look", [:])]), Fixtures.text("Вижу Safari.")], tools: [PictureTool()])
        _ = await collect(await conv.send("глянь"))
        let history = await conv.history
        let result = history[2]["content"]?.arrayValue?.first
        #expect(result?["tool_use_id"] == "toolu_9")
        #expect(result?["content"] == [
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": "AAAA"]],
            ["type": "text", "text": "Скриншот"],
        ])
    }

    @Test func parallelToolResultsInOneMessage() async {
        let (conv, _) = make([Fixtures.toolCall([("a", "open_app", ["x": "1"]), ("b", "open_app", ["x": "2"])]), Fixtures.text("Готово.")])
        _ = await collect(await conv.send("открой два"))
        let history = await conv.history
        #expect(history.count == 4)
        #expect(history[2]["content"]?.arrayValue?.count == 2)
        #expect(history[2]["content"]?.arrayValue?.map { $0["tool_use_id"] } == ["a", "b"])
    }

    @Test func deniedToolIsNotAnAct() async {
        let tool = RecordingTool(name: "quit_app", dangerous: true)
        let (conv, _) = make([Fixtures.toolCall([("t", "quit_app", ["x": "Safari"])]), Fixtures.text("Ладно, не закрываю.")], tools: [tool], confirm: .no)
        let events = await collect(await conv.send("закрой сафари"))
        #expect(events.contains(.toolFinished("quit_app", ran: false)))
        #expect(events.last == .finished(text: "Ладно, не закрываю.", didAct: false))
        #expect(await tool.runs.value == 0)
    }

    @Test func cancelRollsBackHistory() async throws {
        let (conv, client) = make([Fixtures.text("Первый ответ."), Fixtures.toolCall([("t", "open_app", ["x": "1"])]), .hang])
        _ = await collect(await conv.send("раз"))
        let snapshot = await conv.history
        let stream = await conv.send("два")
        let collector = Task { await collect(stream) }
        for _ in 0..<200 where client.requests.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(client.requests.count == 3)
        await conv.cancel()
        let events = await collector.value
        #expect(!events.contains { if case .finished = $0 { true } else { false } })
        #expect(await conv.history == snapshot)
    }

    @Test func errorEmitsFailedAndRollsBack() async {
        let (conv, _) = make([.fail(.network)])
        let events = await collect(await conv.send("привет"))
        #expect(events == [.failed(.network)])
        #expect(await conv.history.isEmpty)
    }

    @Test func roundLimit() async {
        let steps = (0..<9).map { Fixtures.toolCall([("t\($0)", "open_app", ["x": "1"])]) }
        let (conv, client) = make(steps)
        let events = await collect(await conv.send("крутись"))
        #expect(client.requests.count == 8)
        guard case .finished(let text, _) = events.last else {
            Issue.record("no finished event")
            return
        }
        #expect(text == "Я запутался, давай попробуем по-другому.")
    }

    @Test func remarkConsumedOnce() async {
        let (conv, client) = make([Fixtures.text("Хорошо."), Fixtures.text("Ок.")])
        await conv.noteRemark("Как дела?")
        _ = await collect(await conv.send("нормально"))
        _ = await collect(await conv.send("а ты?"))
        let first = client.requests[0].messages.last?["content"]?.stringValue ?? ""
        let second = client.requests[1].messages.last?["content"]?.stringValue ?? ""
        #expect(first.contains("[Джміль только что сказал: «Как дела?»]"))
        #expect(!second.contains("Джміль только что сказал"))
    }

    @Test func staleSessionResetsAfterSilence() async {
        let (conv, _) = make([Fixtures.text("Привет.")])
        _ = await collect(await conv.send("привет"))
        clock.advance(29 * 60)
        await conv.resetIfStale()
        #expect(await conv.history.count == 2)
        clock.advance(2 * 60)
        await conv.resetIfStale()
        #expect(await conv.history.isEmpty)
    }

    @Test func staleSessionResetsAfterSixtyMessages() async {
        let (conv, _) = make((0..<30).map { _ in Fixtures.text("Ок.") })
        for _ in 0..<30 { _ = await collect(await conv.send("ещё")) }
        #expect(await conv.history.count == 60)
        await conv.resetIfStale()
        #expect(await conv.history.isEmpty)
    }

    @Test func emptyReplyAfterToolRollsBack() async {
        let empty = FakeClaudeClient.Step.reply(deltas: [], message: AssistantMessage(content: [], stopReason: "end_turn"))
        let (conv, _) = make([Fixtures.toolCall([("t", "open_app", ["x": "1"])]), empty])
        let events = await collect(await conv.send("открой"))
        #expect(events.last == .finished(text: "", didAct: true))
        #expect(await conv.history.isEmpty)
    }

    @Test func truncatedToolUseFails() async {
        let truncated = FakeClaudeClient.Step.reply(deltas: [], message: AssistantMessage(content: [["type": "tool_use", "id": "t", "name": "open_app", "input": ["x": "1"]]], stopReason: "max_tokens"))
        let (conv, _) = make([truncated])
        let events = await collect(await conv.send("открой"))
        #expect(events == [.failed(.incomplete)])
        #expect(await conv.history.isEmpty)
    }

    @Test func badRequestResetsSession() async {
        let (conv, _) = make([Fixtures.text("Привет."), .fail(.api(status: 400, message: "bad"))])
        _ = await collect(await conv.send("привет"))
        #expect(await conv.history.count == 2)
        let events = await collect(await conv.send("ещё"))
        #expect(events == [.failed(.api(status: 400, message: "bad"))])
        #expect(await conv.history.isEmpty)
    }

    @Test func systemIsFrozenWithinSession() async {
        let client = FakeClaudeClient([Fixtures.text("Раз."), Fixtures.text("Два."), Fixtures.text("Три.")])
        let profile = ProfileBox("Профиль А")
        let conv = Conversation(client: client, executor: ToolExecutor(tools: [], confirmer: ScriptedConfirmer(mode: .yes)),
                                settings: { ConversationSettings(model: "claude-opus-5-5", effort: "low") },
                                profile: { profile.value })
        _ = await collect(await conv.send("раз"))
        profile.value = "Профиль Б"
        _ = await collect(await conv.send("два"))
        #expect(client.requests[1].system == client.requests[0].system)
        await conv.resetSession()
        _ = await collect(await conv.send("три"))
        #expect(client.requests[2].system.contains("Профиль Б"))
    }

    @Test func systemAndToolsAreStableAcrossRounds() async throws {
        let (conv, client) = make([Fixtures.toolCall([("t", "open_app", ["x": "1"])]), Fixtures.text("Да.")])
        _ = await collect(await conv.send("сделай"))
        let reqs = client.requests
        #expect(reqs.count == 2)
        #expect(reqs[0].system == reqs[1].system)
        #expect(try JSONValue.array(reqs[0].tools).encodedData() == JSONValue.array(reqs[1].tools).encodedData())
        #expect(try JSONValue.array(Array(reqs[1].messages.prefix(1))).encodedData() == JSONValue.array(reqs[0].messages).encodedData())
    }
}

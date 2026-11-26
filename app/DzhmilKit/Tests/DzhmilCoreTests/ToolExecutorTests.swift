import Foundation
import Testing
@testable import DzhmilCore

actor Counter {
    var value = 0
    func increment() { value += 1 }
}

struct RecordingTool: Tool {
    let name: String
    var description = "test tool"
    var inputSchema: JSONValue = ["type": "object", "properties": ["x": ["type": "string"]], "required": ["x"]]
    var dangerous = false
    var output = "done"
    var failure: String?
    var readsUntrustedContent = false
    var asksAfterUntrustedContent = false
    let runs = Counter()

    func risk(for input: JSONValue) -> ToolRisk { dangerous ? .needsConfirmation : .safe }
    func confirmation(for input: JSONValue, language: Language) -> ConfirmationRequest {
        ConfirmationRequest(question: language.pick("Do \(name)?", "Выполнить \(name)?"), detail: nil)
    }
    func run(_ input: JSONValue) async throws -> String {
        await runs.increment()
        if let failure { throw ToolError.message(failure) }
        return output
    }
}

struct PictureTool: Tool {
    let name = "look"
    let description = "picture tool"
    let inputSchema: JSONValue = ["type": "object", "properties": [:], "required": []]
    func risk(for input: JSONValue) -> ToolRisk { .safe }
    func confirmation(for input: JSONValue, language: Language) -> ConfirmationRequest { ConfirmationRequest(question: "", detail: nil) }
    func run(_ input: JSONValue) async throws -> String { "unused" }
    func runRich(_ input: JSONValue) async throws -> ToolRichOutput {
        ToolRichOutput(text: "Screenshot", images: [ToolImage(mediaType: "image/jpeg", base64: "AAAA")])
    }
}

struct ScriptedConfirmer: ConfirmationProvider {
    enum Mode: Sendable { case yes, no, never }
    let mode: Mode
    let asked = Counter()

    func confirm(_ r: ConfirmationRequest) async -> Bool {
        await asked.increment()
        switch mode {
        case .yes: return true
        case .no: return false
        case .never:
            try? await Task.sleep(for: .seconds(1000))
            return true
        }
    }
}

struct AnsweringConfirmer: ConfirmationProvider {
    let answerAfter: Duration

    func confirm(_ r: ConfirmationRequest) async -> Bool {
        try? await Task.sleep(for: answerAfter)
        return true
    }

    func isAnswering() async -> Bool { true }
}

@Suite struct ToolExecutorTests {
    func use(_ name: String) -> ToolUse { ToolUse(id: "t1", name: name, input: ["x": "1"]) }

    @Test func safeToolRunsWithoutAsking() async {
        let tool = RecordingTool(name: "safe")
        let confirmer = ScriptedConfirmer(mode: .no)
        let outcome = await ToolExecutor(tools: [tool], confirmer: confirmer).execute(use("safe"))
        #expect(outcome == ToolOutcome(content: "done", isError: false, ran: true))
        #expect(await confirmer.asked.value == 0)
    }

    @Test func dangerousToolNeverRunsOnNo() async {
        let tool = RecordingTool(name: "danger", dangerous: true)
        let outcome = await ToolExecutor(tools: [tool], confirmer: ScriptedConfirmer(mode: .no)).execute(use("danger"))
        #expect(outcome == ToolOutcome(content: "The user declined; the action was not performed.", isError: false, ran: false))
        #expect(await tool.runs.value == 0)
    }

    @Test func dangerousToolTimesOut() async {
        let tool = RecordingTool(name: "danger", dangerous: true)
        let started = Date()
        let outcome = await ToolExecutor(tools: [tool], confirmer: ScriptedConfirmer(mode: .never), confirmTimeout: .milliseconds(200)).execute(use("danger"))
        #expect(outcome == ToolOutcome(content: "The user didn't answer; the action was not performed.", isError: false, ran: false))
        #expect(await tool.runs.value == 0)
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test func timeoutWaitsWhileTheUserIsAnswering() async {
        let tool = RecordingTool(name: "danger", dangerous: true)
        let confirmer = AnsweringConfirmer(answerAfter: .milliseconds(400))
        let outcome = await ToolExecutor(tools: [tool], confirmer: confirmer, confirmTimeout: .milliseconds(100)).execute(use("danger"))
        #expect(outcome.ran)
        #expect(await tool.runs.value == 1)
    }

    @Test func answeringCannotHoldTheQuestionForever() async {
        let tool = RecordingTool(name: "danger", dangerous: true)
        let started = Date()
        let executor = ToolExecutor(tools: [tool], confirmer: AnsweringConfirmer(answerAfter: .seconds(1000)),
                                    confirmTimeout: .milliseconds(100), answerGrace: .milliseconds(300))
        let outcome = await executor.execute(use("danger"))
        #expect(outcome.content == "The user didn't answer; the action was not performed.")
        #expect(await tool.runs.value == 0)
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test func dangerousToolRunsOnYes() async {
        let tool = RecordingTool(name: "danger", dangerous: true)
        let outcome = await ToolExecutor(tools: [tool], confirmer: ScriptedConfirmer(mode: .yes)).execute(use("danger"))
        #expect(outcome.ran)
        #expect(await tool.runs.value == 1)
    }

    @Test func unknownToolIsError() async {
        let outcome = await ToolExecutor(tools: [], confirmer: ScriptedConfirmer(mode: .yes)).execute(use("ghost"))
        #expect(outcome.isError)
        #expect(!outcome.ran)
        #expect(outcome.content.contains("ghost"))
    }

    @Test func throwingToolIsError() async {
        let tool = RecordingTool(name: "boom", failure: "boom happened")
        let outcome = await ToolExecutor(tools: [tool], confirmer: ScriptedConfirmer(mode: .yes)).execute(use("boom"))
        #expect(outcome == ToolOutcome(content: "boom happened", isError: true, ran: true))
    }

    @Test func definitionsAreStrict() {
        let executor = ToolExecutor(tools: [RecordingTool(name: "a"), RecordingTool(name: "b")], confirmer: ScriptedConfirmer(mode: .yes))
        #expect(executor.definitions.count == 2)
        for d in executor.definitions {
            #expect(d["strict"] == .bool(true))
            #expect(d["input_schema"]?["additionalProperties"] == .bool(false))
            #expect(d["name"]?.stringValue != nil)
            #expect(d["description"]?.stringValue != nil)
        }
    }

    @Test func outputIsLimited() async {
        let tool = RecordingTool(name: "loud", output: String(repeating: "a", count: 10_000))
        let outcome = await ToolExecutor(tools: [tool], confirmer: ScriptedConfirmer(mode: .yes)).execute(use("loud"))
        #expect(outcome.content.count <= 4100)
    }

    @Test func imageToolReturnsImages() async {
        let outcome = await ToolExecutor(tools: [PictureTool()], confirmer: ScriptedConfirmer(mode: .yes)).execute(ToolUse(id: "t", name: "look", input: [:]))
        #expect(outcome.content == "Screenshot")
        #expect(outcome.images == [ToolImage(mediaType: "image/jpeg", base64: "AAAA")])
        #expect(outcome.ran && !outcome.isError)
    }

    @Test func plainToolHasNoImages() async {
        let outcome = await ToolExecutor(tools: [RecordingTool(name: "safe")], confirmer: ScriptedConfirmer(mode: .yes)).execute(use("safe"))
        #expect(outcome.images.isEmpty)
    }

    @Test func limitTruncates() {
        let s = ToolOutput.limit(String(repeating: "a", count: 10_000))
        #expect(s.count <= 4100)
        #expect(s.hasSuffix("…[cut, 10000 characters in total]"))
        #expect(ToolOutput.limit("short") == "short")
    }
}

@Suite struct UntrustedToolFlagsTests {
    @Test func memoryAndLinksAskAfterScreenOrClipboard() throws {
        let tools = MacToolbox.all(timers: TimerStore(), screen: NoScreen(), profile: ProfileStore(directory: FileManager.default.temporaryDirectory),
                                   clipboard: NoClipboard())
        let readers = Set(tools.filter(\.readsUntrustedContent).map(\.name))
        let guarded = Set(tools.filter(\.asksAfterUntrustedContent).map(\.name))
        #expect(readers == ["look_at_screen", "read_clipboard"])
        #expect(guarded == ["remember", "forget", "open_url"])
        let remember = try #require(tools.first { $0.name == "remember" })
        #expect(remember.confirmation(for: ["fact": "  Interview   on Thursday "], language: .english) == ConfirmationRequest(question: "Remember this?", detail: "Interview on Thursday"))
    }

    @Test func executorAsksOnlyWhenTold() async {
        let tool = RecordingTool(name: "remember", asksAfterUntrustedContent: true)
        let confirmer = ScriptedConfirmer(mode: .no)
        let executor = ToolExecutor(tools: [tool], confirmer: confirmer)
        let free = await executor.execute(ToolUse(id: "1", name: "remember", input: ["x": "a"]))
        #expect(free.ran)
        let guarded = await executor.execute(ToolUse(id: "2", name: "remember", input: ["x": "a"]), afterUntrustedContent: true)
        #expect(!guarded.ran)
        #expect(await confirmer.asked.value == 1)
    }
}

private struct NoScreen: ScreenCapturer {
    func capture(_ target: CaptureTarget) async throws -> CapturedImage { throw ScreenCaptureError.permissionDenied }
}

private struct NoClipboard: ClipboardReader {
    func read() async -> ClipboardContent { .empty }
}

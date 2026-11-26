import Foundation

public struct ConversationSettings: Equatable, Sendable {
    public var provider: Provider
    public var model: String
    public var effort: String
    public var language: Language

    public init(model: String, effort: String, provider: Provider = .anthropic, language: Language = .english) {
        self.language = language
        self.provider = provider
        self.model = model
        self.effort = effort
    }
}

public enum ConversationEvent: Equatable, Sendable {
    case sentence(String)
    case emotion(Emotion)
    case toolStarted(String)
    case toolFinished(String, ran: Bool)
    case finished(text: String, didAct: Bool)
    case failed(ChatError)
}

public actor Conversation {
    static let maxRounds = 8
    static let staleAfter: TimeInterval = 30 * 60
    static let maxMessages = 60
    static func lostMessage(_ language: Language) -> String {
        language.pick("I got confused, let's try another way.", "Что-то я запутался, давай попробуем иначе.")
    }

    private let client: any ChatClient
    private let executor: ToolExecutor
    private let settings: @Sendable () -> ConversationSettings
    private let profile: @Sendable () -> String
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone

    public private(set) var history: [JSONValue] = []
    private var lastActivity: Date?
    private var pendingRemark: String?
    private var turnSnapshot: [JSONValue]?
    private var sessionSystem: String?
    private var sessionSettings: ConversationSettings?
    private var sawUntrustedContent = false
    private var currentTask: Task<Void, Never>?
    private var generation = 0
    private var resetPending = false

    public init(client: any ChatClient, executor: ToolExecutor,
                settings: @escaping @Sendable () -> ConversationSettings,
                profile: @escaping @Sendable () -> String,
                now: @escaping @Sendable () -> Date = { Date() },
                timeZone: TimeZone = .current) {
        self.client = client
        self.executor = executor
        self.settings = settings
        self.profile = profile
        self.now = now
        self.timeZone = timeZone
    }

    public func noteRemark(_ text: String) {
        pendingRemark = text
    }

    public func resetIfStale() {
        guard turnSnapshot == nil else { return }
        let silent = lastActivity.map { now().timeIntervalSince($0) >= Self.staleAfter } ?? false
        if silent || history.count >= Self.maxMessages {
            clearSession()
        }
    }

    public func resetSession() {
        if turnSnapshot == nil {
            clearSession()
        } else {
            resetPending = true
        }
    }

    private func clearSession() {
        history = []
        lastActivity = nil
        sessionSystem = nil
        sessionSettings = nil
        sawUntrustedContent = false
        resetPending = false
    }

    public func cancel() {
        guard let snapshot = turnSnapshot else { return }
        generation += 1
        currentTask?.cancel()
        currentTask = nil
        history = snapshot
        turnSnapshot = nil
    }

    public func send(_ text: String) -> AsyncStream<ConversationEvent> {
        cancel()
        let s = settings()
        let changed = sessionSettings.map { ($0.provider, $0.language) != (s.provider, s.language) } ?? false
        if resetPending || changed { clearSession() }
        resetIfStale()
        sessionSettings = s
        let (stream, continuation) = AsyncStream.makeStream(of: ConversationEvent.self)
        generation += 1
        let gen = generation
        turnSnapshot = history
        let system = sessionSystem ?? PromptBuilder.system(profile: profile(), language: s.language)
        sessionSystem = system
        let content = PromptBuilder.userTurn(text, now: now(), timeZone: timeZone, remark: pendingRemark)
        pendingRemark = nil
        appendUserText(content)
        lastActivity = now()
        currentTask = Task { await self.runTurn(gen: gen, system: system, settings: s, continuation: continuation) }
        return stream
    }

    private func appendUserText(_ text: String) {
        if case .object(var last)? = history.last, last["role"] == "user", case .array(var blocks)? = last["content"] {
            blocks.append(["type": "text", "text": .string(text)])
            last["content"] = .array(blocks)
            history[history.count - 1] = .object(last)
        } else {
            history.append(["role": "user", "content": .string(text)])
        }
    }

    private func isCurrent(_ gen: Int) -> Bool {
        gen == generation && !Task.isCancelled
    }

    private func rollback(_ gen: Int) {
        guard gen == generation, let snapshot = turnSnapshot else { return }
        history = snapshot
        turnSnapshot = nil
    }

    private func complete(_ gen: Int) {
        guard gen == generation else { return }
        turnSnapshot = nil
        currentTask = nil
        lastActivity = now()
    }

    private func runTurn(gen: Int, system: String, settings s: ConversationSettings, continuation: AsyncStream<ConversationEvent>.Continuation) async {
        defer { continuation.finish() }
        var splitter = SentenceSplitter()
        var emotions = EmotionFilter()
        var fullText = ""
        var markupSeen = false
        var retriedMarkup = false
        func emit(_ sentence: String) {
            guard !markupSeen else { return }
            guard ToolMarkup.contains(sentence) else {
                continuation.yield(.sentence(sentence))
                return
            }
            markupSeen = true
            let clean = ToolMarkup.strip(sentence)
            if !clean.isEmpty { continuation.yield(.sentence(clean)) }
        }
        func pass(_ pieces: [EmotionPiece]) {
            for piece in pieces where !markupSeen {
                switch piece {
                case .text(let t):
                    fullText += t
                    for sentence in splitter.feed(t) { emit(sentence) }
                case .emotion(let e):
                    continuation.yield(.emotion(e))
                }
            }
        }
        var didAct = false
        let tools = executor.definitions

        for _ in 0..<Self.maxRounds {
            let request = MessagesRequest(model: s.model, system: system, messages: history, tools: tools, effort: s.effort, provider: s.provider)
            var final: AssistantMessage?
            do {
                for try await event in client.stream(request) {
                    guard isCurrent(gen) else { break }
                    switch event {
                    case .textDelta(let d):
                        pass(emotions.feed(d))
                    case .message(let m):
                        final = m
                    }
                }
            } catch {
                guard isCurrent(gen) else { return }
                rollback(gen)
                let chatError = error as? ChatError ?? .network
                Log.conversation.error("Turn failed: \(String(describing: chatError), privacy: .public)")
                if case .api(let status, _) = chatError, (400..<500).contains(status) { clearSession() }
                currentTask = nil
                continuation.yield(.failed(chatError))
                return
            }
            guard isCurrent(gen) else { return }
            guard let message = final else {
                rollback(gen)
                continuation.yield(.failed(.network))
                return
            }
            let uses = message.toolUses
            if message.content.isEmpty {
                rollback(gen)
                currentTask = nil
                continuation.yield(.finished(text: fullText, didAct: didAct))
                return
            }
            if message.stopReason != "tool_use", !uses.isEmpty {
                Log.conversation.error("Tool call cut off, stop reason \(message.stopReason ?? "none", privacy: .public)")
                rollback(gen)
                currentTask = nil
                continuation.yield(.failed(.incomplete))
                return
            }
            pass(emotions.flush())
            if let rest = splitter.flush() { emit(rest) }
            if markupSeen, uses.isEmpty {
                fullText = ToolMarkup.strip(fullText)
                guard !retriedMarkup else {
                    Log.conversation.error("Tool call written as text again, giving up")
                    rollback(gen)
                    currentTask = nil
                    continuation.yield(.sentence(Self.lostMessage(s.language)))
                    continuation.yield(.finished(text: Self.lostMessage(s.language), didAct: didAct))
                    return
                }
                Log.conversation.error("Tool call written as text, asking again")
                retriedMarkup = true
                markupSeen = false
                splitter = SentenceSplitter()
                emotions = EmotionFilter()
                if !fullText.isEmpty, !fullText.hasSuffix(" ") { fullText += " " }
                continue
            }
            history.append(message.asHistoryEntry)

            guard message.stopReason == "tool_use", !uses.isEmpty else {
                complete(gen)
                continuation.yield(.finished(text: fullText, didAct: didAct))
                return
            }

            if !fullText.isEmpty, !fullText.hasSuffix(" ") { fullText += " " }
            var results: [JSONValue] = []
            for use in uses {
                continuation.yield(.toolStarted(use.name))
                let outcome = await executor.execute(use, afterUntrustedContent: sawUntrustedContent, language: s.language)
                guard isCurrent(gen) else { return }
                if outcome.ran, executor.readsUntrustedContent(use.name) { sawUntrustedContent = true }
                if outcome.ran && !outcome.isError { didAct = true }
                continuation.yield(.toolFinished(use.name, ran: outcome.ran))
                var result: [String: JSONValue] = [
                    "type": "tool_result",
                    "tool_use_id": .string(use.id),
                    "content": Self.resultContent(outcome),
                ]
                if outcome.isError { result["is_error"] = true }
                results.append(.object(result))
            }
            history.append(["role": "user", "content": .array(results)])
            turnSnapshot = history
        }

        Log.conversation.error("Gave up after \(Self.maxRounds) tool rounds")
        rollback(gen)
        currentTask = nil
        continuation.yield(.sentence(Self.lostMessage(s.language)))
        continuation.yield(.finished(text: Self.lostMessage(s.language), didAct: didAct))
    }

    static func resultContent(_ outcome: ToolOutcome) -> JSONValue {
        guard !outcome.images.isEmpty else { return .string(outcome.content) }
        var blocks: [JSONValue] = outcome.images.map {
            ["type": "image", "source": ["type": "base64", "media_type": .string($0.mediaType), "data": .string($0.base64)]]
        }
        blocks.append(["type": "text", "text": .string(outcome.content)])
        return .array(blocks)
    }
}

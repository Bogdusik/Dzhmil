import Foundation

public actor ToolExecutor {
    static let declined = "Пользователь отказался, действие не выполнено."
    static let noAnswer = "Пользователь не ответил, действие не выполнено."

    private let tools: [String: any Tool]
    private let confirmer: any ConfirmationProvider
    private let confirmTimeout: Duration
    private let answerGrace: Duration
    public nonisolated let definitions: [JSONValue]

    public init(tools: [any Tool], confirmer: any ConfirmationProvider, confirmTimeout: Duration = .seconds(20), answerGrace: Duration = .seconds(90)) {
        self.tools = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.confirmer = confirmer
        self.confirmTimeout = confirmTimeout
        self.answerGrace = answerGrace
        self.definitions = tools.map { tool in
            var schema = tool.inputSchema
            if case .object(var o) = schema {
                o["additionalProperties"] = false
                if o["properties"] == nil { o["properties"] = .object([:]) }
                if o["required"] == nil { o["required"] = .array([]) }
                schema = .object(o)
            }
            return [
                "name": .string(tool.name),
                "description": .string(tool.description),
                "input_schema": schema,
                "strict": true,
            ]
        }
    }

    public func execute(_ use: ToolUse) async -> ToolOutcome {
        guard let tool = tools[use.name] else {
            return ToolOutcome(content: "Нет такого инструмента: \(use.name)", isError: true, ran: false)
        }
        if tool.risk(for: use.input) == .needsConfirmation {
            switch await confirm(tool.confirmation(for: use.input)) {
            case .some(true):
                Log.tools.notice("\(use.name, privacy: .public): confirmed")
            case .some(false):
                Log.tools.notice("\(use.name, privacy: .public): declined")
                return ToolOutcome(content: Self.declined, isError: false, ran: false)
            case .none:
                Log.tools.notice("\(use.name, privacy: .public): no answer")
                return ToolOutcome(content: Self.noAnswer, isError: false, ran: false)
            }
        }
        do {
            let output = try await tool.runRich(use.input)
            Log.tools.notice("\(use.name, privacy: .public): ran")
            return ToolOutcome(content: ToolOutput.limit(output.text, max: tool.outputLimit), isError: false, ran: true, images: output.images)
        } catch {
            Log.tools.error("\(use.name, privacy: .public) failed: \(error.localizedDescription, privacy: .private)")
            return ToolOutcome(content: ToolOutput.limit(error.localizedDescription), isError: true, ran: true)
        }
    }

    private func confirm(_ request: ConfirmationRequest) async -> Bool? {
        let confirmer = self.confirmer
        let timeout = self.confirmTimeout
        let grace = self.answerGrace
        return await withTaskGroup(of: Bool?.self) { group in
            group.addTask { await confirmer.confirm(request) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                let deadline = ContinuousClock.now + grace
                while !Task.isCancelled, ContinuousClock.now < deadline, await confirmer.isAnswering() {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

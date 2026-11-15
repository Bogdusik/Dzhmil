import Foundation

public actor ToolExecutor {
    static let declined = "Пользователь отказался, действие не выполнено."
    static let noAnswer = "Пользователь не ответил, действие не выполнено."

    private let tools: [String: any Tool]
    private let confirmer: any ConfirmationProvider
    private let confirmTimeout: Duration
    public nonisolated let definitions: [JSONValue]

    public init(tools: [any Tool], confirmer: any ConfirmationProvider, confirmTimeout: Duration = .seconds(20)) {
        self.tools = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.confirmer = confirmer
        self.confirmTimeout = confirmTimeout
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
            case .some(true): break
            case .some(false): return ToolOutcome(content: Self.declined, isError: false, ran: false)
            case .none: return ToolOutcome(content: Self.noAnswer, isError: false, ran: false)
            }
        }
        do {
            let output = try await tool.run(use.input)
            return ToolOutcome(content: ToolOutput.limit(output), isError: false, ran: true)
        } catch {
            return ToolOutcome(content: ToolOutput.limit(error.localizedDescription), isError: true, ran: true)
        }
    }

    private func confirm(_ request: ConfirmationRequest) async -> Bool? {
        let confirmer = self.confirmer
        let timeout = self.confirmTimeout
        return await withTaskGroup(of: Bool?.self) { group in
            group.addTask { await confirmer.confirm(request) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

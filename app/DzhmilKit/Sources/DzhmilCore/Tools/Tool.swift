import Foundation

public enum ToolRisk: Sendable {
    case safe, needsConfirmation
}

public struct ConfirmationRequest: Equatable, Sendable {
    public var question: String
    public var detail: String?

    public init(question: String, detail: String?) {
        self.question = question
        self.detail = detail
    }
}

public protocol ConfirmationProvider: Sendable {
    func confirm(_ request: ConfirmationRequest) async -> Bool
}

public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: JSONValue { get }
    func risk(for input: JSONValue) -> ToolRisk
    func confirmation(for input: JSONValue) -> ConfirmationRequest
    func run(_ input: JSONValue) async throws -> String
}

public enum ToolError: LocalizedError, Equatable {
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .message(let m): m
        }
    }
}

public struct ToolOutcome: Equatable, Sendable {
    public var content: String
    public var isError: Bool
    public var ran: Bool

    public init(content: String, isError: Bool, ran: Bool) {
        self.content = content
        self.isError = isError
        self.ran = ran
    }
}

public enum ToolOutput {
    public static func limit(_ s: String, max: Int = 4000) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max)) + "\n…[обрезано, всего \(s.count) символов]"
    }
}

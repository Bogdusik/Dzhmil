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
    func isAnswering() async -> Bool
}

extension ConfirmationProvider {
    public func isAnswering() async -> Bool { false }
}

public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: JSONValue { get }
    func risk(for input: JSONValue) -> ToolRisk
    func confirmation(for input: JSONValue) -> ConfirmationRequest
    func run(_ input: JSONValue) async throws -> String
    func runRich(_ input: JSONValue) async throws -> ToolRichOutput
}

extension Tool {
    public func runRich(_ input: JSONValue) async throws -> ToolRichOutput {
        ToolRichOutput(text: try await run(input), images: [])
    }
}

public struct ToolImage: Equatable, Sendable {
    public var mediaType: String
    public var base64: String

    public init(mediaType: String, base64: String) {
        self.mediaType = mediaType
        self.base64 = base64
    }
}

public struct ToolRichOutput: Sendable {
    public var text: String
    public var images: [ToolImage]

    public init(text: String, images: [ToolImage]) {
        self.text = text
        self.images = images
    }
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
    public var images: [ToolImage]

    public init(content: String, isError: Bool, ran: Bool, images: [ToolImage] = []) {
        self.content = content
        self.isError = isError
        self.ran = ran
        self.images = images
    }
}

public enum ToolOutput {
    public static func limit(_ s: String, max: Int = 4000) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max)) + "\n…[обрезано, всего \(s.count) символов]"
    }
}

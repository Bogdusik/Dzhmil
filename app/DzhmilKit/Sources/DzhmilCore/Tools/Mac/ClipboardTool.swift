import Foundation

public enum ClipboardContent: Equatable, Sendable {
    case text(String), concealed, empty, notText
}

public protocol ClipboardReader: Sendable {
    func read() async -> ClipboardContent
}

struct ReadClipboardTool: SafeTool {
    static let maxCharacters = 8000

    let reader: any ClipboardReader
    let beforeRead: @Sendable () async -> Bool
    let name = "read_clipboard"
    let description = "Read the text the user copied: an error, code or a message. Call it only when they ask about what they copied."
    let inputSchema = Schema.object([:])
    var outputLimit: Int { Self.maxCharacters + 200 }

    func run(_ input: JSONValue) async throws -> String {
        guard await beforeRead() else {
            throw ToolError.message("I'm hidden right now. Call me back and ask again.")
        }
        try Task.checkCancellation()
        switch await reader.read() {
        case .concealed:
            throw ToolError.message("Something secret is copied, like a password. I don't read that.")
        case .notText:
            throw ToolError.message("What's copied isn't text. Copy the error text and ask again.")
        case .empty:
            throw ToolError.message("The clipboard is empty.")
        case .text(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError.message("The clipboard is empty.") }
            let cut = text.count > Self.maxCharacters
                ? String(text.prefix(Self.maxCharacters)) + "\n…[cut, \(text.count) characters in total]"
                : text
            return "Copied text (\(text.count) characters):\n" + cut
        }
    }
}

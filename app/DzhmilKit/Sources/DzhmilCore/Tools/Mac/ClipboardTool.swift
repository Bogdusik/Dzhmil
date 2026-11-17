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
    let description = "Прочитать текст, который пользователь скопировал: ошибку, код, сообщение. Вызывай, только когда он спрашивает про скопированное."
    let inputSchema = Schema.object([:])
    var outputLimit: Int { Self.maxCharacters + 200 }

    func run(_ input: JSONValue) async throws -> String {
        guard await beforeRead() else {
            throw ToolError.message("Я сейчас спрятан. Позови меня и попроси ещё раз.")
        }
        try Task.checkCancellation()
        switch await reader.read() {
        case .concealed:
            throw ToolError.message("Там скопировано что-то секретное, например пароль. Такое я не читаю.")
        case .notText:
            throw ToolError.message("Скопирован не текст. Скопируй текст ошибки и спроси ещё раз.")
        case .empty:
            throw ToolError.message("Буфер обмена пуст.")
        case .text(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError.message("Буфер обмена пуст.") }
            let cut = text.count > Self.maxCharacters
                ? String(text.prefix(Self.maxCharacters)) + "\n…[обрезано, всего \(text.count) символов]"
                : text
            return "Скопированный текст (\(text.count) символов):\n" + cut
        }
    }
}

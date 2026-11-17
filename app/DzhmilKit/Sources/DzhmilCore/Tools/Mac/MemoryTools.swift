import Foundation

public enum MemoryNotes {
    static let header = "## Запомнил"
    static let maxLength = 200
    static let maxFacts = 50
    static let minQuery = 3

    static func clean(_ fact: String) -> String {
        fact.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func section(_ lines: [String]) -> (header: Int, end: Int)? {
        guard let h = lines.firstIndex(of: header) else { return nil }
        let end = lines[(h + 1)...].firstIndex { $0.hasPrefix("## ") } ?? lines.count
        return (h, end)
    }

    private static func factIndices(_ lines: [String]) -> [Int] {
        guard let s = section(lines) else { return [] }
        return ((s.header + 1)..<s.end).filter { lines[$0].hasPrefix("- ") }
    }

    public static func facts(in text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        return factIndices(lines).map { String(lines[$0].dropFirst(2)) }
    }

    public static func adding(_ fact: String, to text: String) throws -> String {
        let f = clean(fact)
        guard !f.isEmpty else { throw ToolError.message("Нечего запоминать.") }
        guard f.count <= maxLength else { throw ToolError.message("Слишком длинно, сформулируй до \(maxLength) символов.") }
        let existing = facts(in: text)
        if existing.contains(where: { $0.lowercased() == f.lowercased() }) { return text }
        guard existing.count < maxFacts else { throw ToolError.message("Память заполнена: \(maxFacts) пунктов. Попроси меня что-то забыть.") }

        var lines = text.components(separatedBy: "\n")
        guard let s = section(lines) else {
            if text.isEmpty { return "\(header)\n- \(f)\n" }
            let base = text.hasSuffix("\n") ? text : text + "\n"
            return base + "\n\(header)\n- \(f)\n"
        }
        let insertAt = (factIndices(lines).last ?? s.header) + 1
        lines.insert("- \(f)", at: insertAt)
        return lines.joined(separator: "\n")
    }

    public static func removing(_ query: String, from text: String) throws -> (String, [String]) {
        let q = clean(query).lowercased()
        guard q.count >= minQuery else { throw ToolError.message("Уточни, что именно забыть.") }
        var lines = text.components(separatedBy: "\n")
        let hits = factIndices(lines).filter { lines[$0].dropFirst(2).lowercased().contains(q) }
        guard !hits.isEmpty else { throw ToolError.message("Не нашёл такого в памяти.") }
        let removed = hits.map { String(lines[$0].dropFirst(2)) }
        for i in hits.reversed() { lines.remove(at: i) }
        return (lines.joined(separator: "\n"), removed)
    }
}

struct RememberTool: SafeTool {
    let profile: ProfileStore
    let name = "remember"
    let description = "Запомнить факт о пользователе надолго, только когда он прямо просит запомнить. Коротко, своими словами, до 200 символов."
    let inputSchema = Schema.object(["fact": Schema.string("Что запомнить, например «Собеседование в четверг в 10:00»")])

    func run(_ input: JSONValue) async throws -> String {
        let fact = try input.requiredString("fact")
        let text = try MemoryNotes.adding(fact, to: profile.load())
        try profile.save(text)
        return "Запомнил: \(MemoryNotes.clean(fact))"
    }
}

struct ForgetTool: SafeTool {
    let profile: ProfileStore
    let name = "forget"
    let description = "Забыть запомненное раньше: удаляет пункты памяти, содержащие этот текст."
    let inputSchema = Schema.object(["query": Schema.string("Слово или часть фразы из пункта, который нужно забыть")])

    func run(_ input: JSONValue) async throws -> String {
        let (text, removed) = try MemoryNotes.removing(try input.requiredString("query"), from: profile.load())
        try profile.save(text)
        return "Забыл: " + removed.joined(separator: "; ")
    }
}

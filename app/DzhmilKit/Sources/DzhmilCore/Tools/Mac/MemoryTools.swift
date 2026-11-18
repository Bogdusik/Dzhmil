import Foundation

public enum MemoryNotes {
    static let header = "## Remembered"
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
        guard !f.isEmpty else { throw ToolError.message("Nothing to remember.") }
        guard f.count <= maxLength else { throw ToolError.message("Too long, keep it under \(maxLength) characters.") }
        let existing = facts(in: text)
        if existing.contains(where: { $0.lowercased() == f.lowercased() }) { return text }
        guard existing.count < maxFacts else { throw ToolError.message("My memory is full: \(maxFacts) items. Ask me to forget something.") }

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
        guard q.count >= minQuery else { throw ToolError.message("Say exactly what to forget.") }
        var lines = text.components(separatedBy: "\n")
        let hits = factIndices(lines).filter { lines[$0].dropFirst(2).lowercased().contains(q) }
        guard !hits.isEmpty else { throw ToolError.message("I couldn't find that in my memory.") }
        let removed = hits.map { String(lines[$0].dropFirst(2)) }
        for i in hits.reversed() { lines.remove(at: i) }
        return (lines.joined(separator: "\n"), removed)
    }
}

struct RememberTool: SafeTool {
    let profile: ProfileStore
    let asksAfterUntrustedContent = true
    let name = "remember"
    let description = "Remember a fact about the user for good, only when they explicitly ask you to. Short, in your own words, up to 200 characters."
    let inputSchema = Schema.object(["fact": Schema.string("What to remember, for example “Job interview on Thursday at 10:00”")])

    func run(_ input: JSONValue) async throws -> String {
        let fact = try input.requiredString("fact")
        let text = try MemoryNotes.adding(fact, to: profile.load())
        try profile.save(text)
        return "Remembered: \(MemoryNotes.clean(fact))"
    }

    func confirmation(for input: JSONValue) -> ConfirmationRequest {
        ConfirmationRequest(question: "Remember this?", detail: input["fact"]?.stringValue.map(MemoryNotes.clean))
    }
}

struct ForgetTool: SafeTool {
    let profile: ProfileStore
    let asksAfterUntrustedContent = true
    let name = "forget"
    let description = "Forget something remembered earlier: removes memory items that contain this text."
    let inputSchema = Schema.object(["query": Schema.string("A word or part of the item to forget")])

    func run(_ input: JSONValue) async throws -> String {
        let (text, removed) = try MemoryNotes.removing(try input.requiredString("query"), from: profile.load())
        try profile.save(text)
        return "Forgot: " + removed.joined(separator: "; ")
    }

    func confirmation(for input: JSONValue) -> ConfirmationRequest {
        ConfirmationRequest(question: "Forget what matches this?", detail: input["query"]?.stringValue)
    }
}

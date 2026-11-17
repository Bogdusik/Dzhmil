import Foundation

public struct SentenceSplitter: Sendable {
    static let terminators: Set<Character> = [".", "!", "?", "…"]
    static let abbreviations: Set<String> = ["e.g", "i.e", "etc", "mr", "mrs", "ms", "dr", "vs", "approx"]

    private var buffer = ""

    public init() {}

    public mutating func feed(_ delta: String) -> [String] {
        buffer += delta
        var out: [String] = []
        var start = buffer.startIndex
        var i = buffer.startIndex
        while i < buffer.endIndex {
            let c = buffer[i]
            if c == "\n" {
                let sentence = buffer[start..<i].trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { out.append(sentence) }
                start = buffer.index(after: i)
                i = start
                continue
            }
            if Self.terminators.contains(c) {
                var j = buffer.index(after: i)
                while j < buffer.endIndex, Self.terminators.contains(buffer[j]) { j = buffer.index(after: j) }
                guard j < buffer.endIndex else { break }
                if buffer[j].isWhitespace, !(c == "." && isAbbreviation(endingAt: i, from: start)) {
                    let sentence = buffer[start..<j].trimmingCharacters(in: .whitespaces)
                    if sentence.count >= 2 {
                        out.append(sentence)
                        start = j
                    }
                }
                i = j
                continue
            }
            i = buffer.index(after: i)
        }
        buffer = String(buffer[start...])
        return out
    }

    public mutating func flush() -> String? {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? nil : rest
    }

    private func isAbbreviation(endingAt dot: String.Index, from start: String.Index) -> Bool {
        var k = dot
        while k > start {
            let prev = buffer.index(before: k)
            if buffer[prev].isWhitespace || buffer[prev] == "," || buffer[prev] == "(" { break }
            k = prev
        }
        return Self.abbreviations.contains(buffer[k..<dot].lowercased())
    }
}

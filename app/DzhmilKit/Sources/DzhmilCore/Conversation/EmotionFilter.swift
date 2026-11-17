import Foundation

public enum Emotion: String, CaseIterable, Sendable {
    case happy, laugh, surprised, thinking, sad
}

public enum EmotionPiece: Equatable, Sendable {
    case text(String)
    case emotion(Emotion)
}

public struct EmotionFilter: Sendable {
    static let maxTagLength = 12

    private var tag: String?
    private var dropSpace = false

    public init() {}

    public mutating func feed(_ delta: String) -> [EmotionPiece] {
        var out: [EmotionPiece] = []
        var text = ""
        func emitText() {
            if !text.isEmpty { out.append(.text(text)) }
            text = ""
        }
        for c in delta {
            if var open = tag {
                if c == ">", open.count > 1 {
                    tag = nil
                    emitText()
                    if let e = Emotion(rawValue: String(open.dropFirst()).lowercased()) { out.append(.emotion(e)) }
                    dropSpace = true
                    continue
                }
                if c.isLetter, c.isASCII, open.count <= Self.maxTagLength {
                    open.append(c)
                    tag = open
                    continue
                }
                tag = nil
                text += open
            }
            if dropSpace {
                dropSpace = false
                if c == " " { continue }
            }
            if c == "<" {
                tag = "<"
            } else {
                text.append(c)
            }
        }
        emitText()
        return out
    }

    public mutating func flush() -> [EmotionPiece] {
        defer {
            tag = nil
            dropSpace = false
        }
        guard let open = tag else { return [] }
        return [.text(open)]
    }

    public static func strip(_ text: String) -> String {
        var f = EmotionFilter()
        return (f.feed(text) + f.flush()).map { piece in
            if case .text(let t) = piece { t } else { "" }
        }.joined()
    }
}

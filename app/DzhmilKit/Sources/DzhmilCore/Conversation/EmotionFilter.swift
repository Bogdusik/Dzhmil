import Foundation

public enum Emotion: String, CaseIterable, Sendable {
    case happy, laugh, surprised, thinking, sad
}

public enum EmotionPiece: Equatable, Sendable {
    case text(String)
    case emotion(Emotion)
}

public struct EmotionFilter: Sendable {
    static let maxTagLength = 16
    static let junkElements: Set<String> = ["thinking_mode"]
    static let maxJunkContent = 40

    private var tag: String?
    private var dropSpace = false
    private var skipping: (closing: String, held: String)?

    public init() {}

    public mutating func feed(_ delta: String) -> [EmotionPiece] {
        var out: [EmotionPiece] = []
        var text = ""
        func emitText() {
            if !text.isEmpty { out.append(.text(text)) }
            text = ""
        }
        for c in delta {
            if var skip = skipping {
                skip.held.append(c)
                if skip.held.hasSuffix(skip.closing) {
                    skipping = nil
                    dropSpace = true
                } else if skip.held.count > Self.maxJunkContent + skip.closing.count {
                    skipping = nil
                    text += skip.held
                } else {
                    skipping = skip
                }
                continue
            }
            if var open = tag {
                if c == ">", open.count > 1, open != "</" {
                    tag = nil
                    emitText()
                    let name = String(open.dropFirst()).lowercased()
                    if let e = Emotion(rawValue: name) {
                        out.append(.emotion(e))
                    } else if Self.junkElements.contains(name) {
                        skipping = ("</\(name)>", "")
                    }
                    dropSpace = true
                    continue
                }
                let isNameCharacter = c.isASCII && (c.isLetter || c == "_")
                let isClosingSlash = c == "/" && open.count == 1
                if isNameCharacter || isClosingSlash, open.count <= Self.maxTagLength {
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
        var rest = tag ?? ""
        if let skip = skipping { rest += skip.held }
        tag = nil
        skipping = nil
        dropSpace = false
        return rest.isEmpty ? [] : [.text(rest)]
    }

    public static func strip(_ text: String) -> String {
        var f = EmotionFilter()
        return (f.feed(text) + f.flush()).map { piece in
            if case .text(let t) = piece { t } else { "" }
        }.joined()
    }
}

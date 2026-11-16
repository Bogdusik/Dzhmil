import Foundation

public enum TranscriptFilter {
    static let hallucinations = [
        "продолжение следует", "субтитры сделал", "субтитры создавал", "субтитры подогнал", "редактор субтитров",
        "спасибо за просмотр", "thank you for watching", "thanks for watching", "дякую за перегляд", "amara.org",
    ]

    public static func clean(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard text.filter(\.isLetter).count >= 2 else { return nil }
        let lower = text.lowercased()
        if lower.count < 60, hallucinations.contains(where: lower.contains) { return nil }
        return text
    }
}

public struct PushToTalkGate: Sendable {
    public enum Outcome: Equatable, Sendable { case tooShort, accept }

    static let minimum: TimeInterval = 0.3
    static let maximum: TimeInterval = 60

    private var downAt: Date?

    public init() {}

    public var isDown: Bool { downAt != nil }

    public mutating func down(at date: Date) {
        downAt = date
    }

    public mutating func up(at date: Date) -> Outcome {
        defer { downAt = nil }
        guard let start = downAt else { return .tooShort }
        return date.timeIntervalSince(start) >= Self.minimum ? .accept : .tooShort
    }

    public func shouldAutoStop(now: Date) -> Bool {
        guard let start = downAt else { return false }
        return now.timeIntervalSince(start) >= Self.maximum
    }
}

public enum YesNoParser {
    static let negative: Set<String> = ["нет", "ні", "нi", "no", "не", "нє", "отмена", "отмени", "стоп", "cancel", "stop", "nope", "неа"]
    static let positive: Set<String> = ["да", "ага", "так", "yes", "давай", "конечно", "угу", "ок", "окей", "ok", "okay", "yeah", "yep",
                                        "роби", "делай", "закрывай", "можно", "верно", "точно", "sure", "звісно", "звичайно", "авжеж"]

    public static func parse(_ text: String) -> Bool? {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        if words.contains(where: negative.contains) { return false }
        if words.contains(where: positive.contains) { return true }
        return nil
    }
}

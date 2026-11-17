import Foundation

public enum TranscriptFilter {
    static let hallucinations = [
        "продолжение следует", "субтитры сделал", "субтитры создавал", "субтитры подогнал", "редактор субтитров",
        "спасибо за просмотр", "thank you for watching", "thanks for watching", "дякую за перегляд", "amara.org",
    ]

    static let wholeUtterance: Set<String> = ["you", "подписывайтесь на канал", "всем пока", "продолжение следует"]

    public static func clean(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard text.filter(\.isLetter).count >= 2 else { return nil }
        let lower = text.lowercased()
        if lower.count < 60, hallucinations.contains(where: lower.contains) { return nil }
        let bare = lower.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        if wholeUtterance.contains(bare) { return nil }
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
                                        "роби", "делай", "закрывай", "выполняй", "запускай", "sure", "звісно", "звичайно", "авжеж"]
    static let fillers: Set<String> = ["ну", "же", "please", "пожалуйста", "будь", "ласка"]
    static let maxWords = 4

    public static func parse(_ text: String) -> Bool? {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        if words.contains(where: negative.contains) { return false }
        guard !words.isEmpty, words.count <= maxWords,
              words.contains(where: positive.contains),
              words.allSatisfy({ positive.contains($0) || fillers.contains($0) }) else { return nil }
        return true
    }
}

public enum AudioLevel {
    static let frameSeconds = 0.03
    static let threshold: Float = 0.006
    static let minimumSpeechSeconds = 0.15

    public static func hasSpeech(_ samples: [Float], sampleRate: Double = 16_000) -> Bool {
        let frame = max(1, Int(sampleRate * frameSeconds))
        let needed = Int((minimumSpeechSeconds / frameSeconds).rounded(.up))
        var loud = 0
        var i = 0
        while i + frame <= samples.count {
            var sum: Float = 0
            for j in i..<(i + frame) { sum += samples[j] * samples[j] }
            if (sum / Float(frame)).squareRoot() > threshold {
                loud += 1
                if loud >= needed { return true }
            }
            i += frame
        }
        return false
    }
}

public struct ConfirmationGate: Sendable {
    static let clickDelay: TimeInterval = 0.4

    public private(set) var currentID: Int?
    private var nextID = 1
    private var shownAt: Date?

    public init() {}

    public mutating func begin(at date: Date) -> Int {
        let id = nextID
        nextID += 1
        currentID = id
        shownAt = date
        return id
    }

    public mutating func resolve(id: Int?) -> Bool {
        guard let id, id == currentID else { return false }
        currentID = nil
        shownAt = nil
        return true
    }

    public func acceptsClick(at date: Date) -> Bool {
        guard let shownAt else { return false }
        return date.timeIntervalSince(shownAt) >= Self.clickDelay
    }
}

public struct SpeechTracker<Action> {
    private var pending = 0
    private var waiters: [Action] = []

    public init() {}

    public var isSpeaking: Bool { pending > 0 }

    public mutating func started() {
        pending += 1
    }

    public mutating func whenIdle(_ action: Action) -> Action? {
        guard pending > 0 else { return action }
        waiters.append(action)
        return nil
    }

    public mutating func finishedOne() -> [Action] {
        guard pending > 0 else { return [] }
        pending -= 1
        guard pending == 0 else { return [] }
        defer { waiters = [] }
        return waiters
    }

    public mutating func reset() {
        pending = 0
        waiters = []
    }
}

extension SpeechTracker: Sendable where Action: Sendable {}

public enum BubbleClick: Sendable {
    case elsewhere, drone, bubble
}

public enum BubbleDismissal {
    public static func shouldDismiss(isReply: Bool, finished: Bool, click: BubbleClick) -> Bool {
        isReply && finished && click != .bubble
    }
}

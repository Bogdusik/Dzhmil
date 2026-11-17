import Foundation
import NaturalLanguage

public struct VoiceInfo: Equatable, Sendable {
    public var identifier: String
    public var language: String
    public var quality: Int
    public var name: String

    public init(identifier: String, language: String, quality: Int, name: String) {
        self.identifier = identifier
        self.language = language
        self.quality = quality
        self.name = name
    }
}

public enum VoiceSelector {
    public static func pick(language: String, from voices: [VoiceInfo]) -> VoiceInfo? {
        voices
            .filter { $0.language.lowercased().hasPrefix(language.lowercased()) }
            .sorted { $0.quality != $1.quality ? $0.quality > $1.quality : $0.name < $1.name }
            .first
    }
}

public enum SpeechText {
    static let russian: [(String, String)] = [("Джміль", "Джмиль"), ("Джмілю", "Джмилю"), ("Джмілем", "Джмилем"), ("Джміля", "Джмиля")]
    static let english: [(String, String)] = [("Джміль", "Dzhmil"), ("Джмілю", "Dzhmil"), ("Джміля", "Dzhmil")]

    public static func forSpeech(_ text: String, language: String) -> String {
        let table: [(String, String)]
        switch language {
        case "ru": table = russian
        case "en": table = english
        default: return text
        }
        var out = text
        for (from, to) in table.sorted(by: { $0.0.count > $1.0.count }) {
            out = out.replacingOccurrences(of: from, with: to)
        }
        return out
    }
}

public enum LanguageGuess {
    static let ukrainianLetters: Set<Character> = ["і", "ї", "є", "ґ", "І", "Ї", "Є", "Ґ"]

    public static func guess(_ original: String) -> String {
        let text = original.replacingOccurrences(of: #"(?i)джміл\p{L}*"#, with: " ", options: .regularExpression)
        guard text.contains(where: \.isLetter) else { return "ru" }
        if text.contains(where: ukrainianLetters.contains) { return "uk" }
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.russian, .ukrainian, .english]
        r.processString(text)
        switch r.dominantLanguage {
        case .ukrainian: return "uk"
        case .english: return "en"
        default: return "ru"
        }
    }
}

import Foundation

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
    public static func pick(for language: Language, from voices: [VoiceInfo]) -> VoiceInfo? {
        let matching = voices.filter { $0.language.lowercased().hasPrefix(language.rawValue) }
        let preferred = matching.filter { $0.language.lowercased() == language.pick("en-gb", "ru-ru") }
        return best(preferred.isEmpty ? matching : preferred)
    }

    private static func best(_ voices: [VoiceInfo]) -> VoiceInfo? {
        voices.sorted { $0.quality != $1.quality ? $0.quality > $1.quality : $0.name < $1.name }.first
    }
}

public enum SpeechText {
    public static func forSpeech(_ text: String, language: Language) -> String {
        guard language == .russian else { return text }
        return text.replacingOccurrences(of: "Dzhmil", with: "Джмиль")
    }
}

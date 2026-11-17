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
    static let preferred = "en-gb"

    public static func pickEnglish(from voices: [VoiceInfo]) -> VoiceInfo? {
        let english = voices.filter { $0.language.lowercased().hasPrefix("en") }
        let british = english.filter { $0.language.lowercased() == preferred }
        return best(british.isEmpty ? english : british)
    }

    private static func best(_ voices: [VoiceInfo]) -> VoiceInfo? {
        voices.sorted { $0.quality != $1.quality ? $0.quality > $1.quality : $0.name < $1.name }.first
    }
}

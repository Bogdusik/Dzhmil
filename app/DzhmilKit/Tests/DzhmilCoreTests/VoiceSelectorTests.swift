import Testing
@testable import DzhmilCore

@Suite struct VoiceSelectorTests {
    let voices = [
        VoiceInfo(identifier: "ru.premium", language: "ru-RU", quality: 3, name: "Milena (Premium)"),
        VoiceInfo(identifier: "us.premium", language: "en-US", quality: 3, name: "Zoe (Premium)"),
        VoiceInfo(identifier: "gb.b", language: "en-GB", quality: 2, name: "Serena B"),
        VoiceInfo(identifier: "gb.a", language: "en-GB", quality: 2, name: "Serena A"),
        VoiceInfo(identifier: "gb.low", language: "en-GB", quality: 1, name: "Daniel"),
    ]

    @Test func prefersBritishEnglishThenQualityThenName() {
        #expect(VoiceSelector.pick(for: .english, from: voices)?.identifier == "gb.a")
    }

    @Test func fallsBackToAnyEnglish() {
        let noBritish = voices.filter { $0.language != "en-GB" }
        #expect(VoiceSelector.pick(for: .english, from: noBritish)?.identifier == "us.premium")
    }

    @Test func noEnglishVoice() {
        #expect(VoiceSelector.pick(for: .english, from: [voices[0]]) == nil)
    }
}

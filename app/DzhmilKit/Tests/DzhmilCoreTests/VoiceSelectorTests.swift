import Testing
@testable import DzhmilCore

@Suite struct VoiceSelectorTests {
    let voices = [
        VoiceInfo(identifier: "ru.default", language: "ru-RU", quality: 1, name: "Milena"),
        VoiceInfo(identifier: "ru.premium", language: "ru-RU", quality: 3, name: "Milena (Premium)"),
        VoiceInfo(identifier: "en.premium", language: "en-US", quality: 3, name: "Zoe (Premium)"),
        VoiceInfo(identifier: "uk.b", language: "uk-UA", quality: 2, name: "Lesya B"),
        VoiceInfo(identifier: "uk.a", language: "uk-UA", quality: 2, name: "Lesya A"),
    ]

    @Test func picksBestQualityForLanguage() {
        #expect(VoiceSelector.pick(language: "ru", from: voices)?.identifier == "ru.premium")
        #expect(VoiceSelector.pick(language: "en", from: voices)?.identifier == "en.premium")
    }

    @Test func sortsByNameOnTie() {
        #expect(VoiceSelector.pick(language: "uk", from: voices)?.identifier == "uk.a")
    }

    @Test func noVoiceForLanguage() {
        #expect(VoiceSelector.pick(language: "de", from: voices) == nil)
    }
}

@Suite struct SpeechTextTests {
    @Test func russianVoicePronouncesName() {
        #expect(SpeechText.forSpeech("Я Джміль! Джмілю нравится.", language: "ru") == "Я Джмиль! Джмилю нравится.")
        #expect(SpeechText.forSpeech("I am Джміль.", language: "en") == "I am Dzhmil.")
    }

    @Test func ukrainianKeepsOriginal() {
        #expect(SpeechText.forSpeech("Я Джміль.", language: "uk") == "Я Джміль.")
    }
}

@Suite struct LanguageGuessTests {
    @Test func detectsLanguages() {
        #expect(LanguageGuess.guess("Привіт, як справи? Що робиш?") == "uk")
        #expect(LanguageGuess.guess("Привет, как дела? Что делаешь?") == "ru")
        #expect(LanguageGuess.guess("Hello, how are you?") == "en")
    }

    @Test func defaultsToRussian() {
        #expect(LanguageGuess.guess("") == "ru")
        #expect(LanguageGuess.guess("42") == "ru")
    }
}

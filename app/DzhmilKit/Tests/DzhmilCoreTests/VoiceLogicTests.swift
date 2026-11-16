import Foundation
import Testing
@testable import DzhmilCore

@Suite struct TranscriptFilterTests {
    @Test func keepsRealSpeech() {
        #expect(TranscriptFilter.clean(" Привет, как дела? ") == "Привет, как дела?")
        #expect(TranscriptFilter.clean("<|ru|> Открой сафари") == "Открой сафари")
        #expect(TranscriptFilter.clean("<|startoftranscript|><|uk|><|transcribe|> Як справи?<|endoftext|>") == "Як справи?")
    }

    @Test(arguments: [
        "", "   ", "[BLANK_AUDIO]", "(музыка)", "[Музыка]", "Продолжение следует...",
        "Субтитры сделал DimaTorzok", "Субтитры создавал DimaTorzok", "Редактор субтитров А.Синецкая",
        "Спасибо за просмотр!", "Thank you for watching.", "Дякую за перегляд!", "а", "...",
    ])
    func dropsNoiseAndHallucinations(_ raw: String) {
        #expect(TranscriptFilter.clean(raw) == nil)
    }
}

@Suite struct PushToTalkGateTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func tooShortPressIsIgnored() {
        var g = PushToTalkGate()
        g.down(at: t0)
        #expect(g.up(at: t0.addingTimeInterval(0.2)) == .tooShort)
    }

    @Test func normalPressIsAccepted() {
        var g = PushToTalkGate()
        g.down(at: t0)
        #expect(g.up(at: t0.addingTimeInterval(1)) == .accept)
    }

    @Test func autoStopsAfterSixtySeconds() {
        var g = PushToTalkGate()
        #expect(!g.shouldAutoStop(now: t0))
        g.down(at: t0)
        #expect(!g.shouldAutoStop(now: t0.addingTimeInterval(59)))
        #expect(g.shouldAutoStop(now: t0.addingTimeInterval(60)))
    }

    @Test func upWithoutDownIsTooShort() {
        var g = PushToTalkGate()
        #expect(g.up(at: t0) == .tooShort)
    }
}

@Suite struct YesNoParserTests {
    @Test(arguments: ["Да", "да, закрывай", "ага", "так", "yes", "давай", "конечно", "угу", "Да.", "так, роби"])
    func yes(_ s: String) { #expect(YesNoParser.parse(s) == true) }

    @Test(arguments: ["нет", "ні", "no", "не надо", "отмена", "стоп", "да нет, не надо", "Нет!", "не треба"])
    func no(_ s: String) { #expect(YesNoParser.parse(s) == false) }

    @Test(arguments: ["может быть", "а что это", ""])
    func unclear(_ s: String) { #expect(YesNoParser.parse(s) == nil) }
}

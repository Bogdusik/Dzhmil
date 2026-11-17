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

@Suite struct HallucinationTests {
    @Test(arguments: ["you", "Подписывайтесь на канал!", "Всем пока!"])
    func dropsWholeUtteranceHallucinations(_ raw: String) {
        #expect(TranscriptFilter.clean(raw) == nil)
    }

    @Test func keepsShortThanks() {
        #expect(TranscriptFilter.clean("Спасибо!") == "Спасибо!")
    }
}

@Suite struct AudioLevelTests {
    func tone(_ seconds: Double, amplitude: Float) -> [Float] {
        (0..<Int(seconds * 16_000)).map { sin(Float($0) * 0.07) * amplitude }
    }

    @Test func silenceIsNotSpeech() {
        #expect(!AudioLevel.hasSpeech([Float](repeating: 0, count: 16_000)))
        #expect(!AudioLevel.hasSpeech((0..<16_000).map { _ in Float.random(in: -0.002...0.002) }))
    }

    @Test func voiceLevelIsSpeech() {
        #expect(AudioLevel.hasSpeech([Float](repeating: 0, count: 8_000) + tone(0.5, amplitude: 0.1)))
    }

    @Test func shortBurstIsNotSpeech() {
        #expect(!AudioLevel.hasSpeech([Float](repeating: 0, count: 16_000) + tone(0.05, amplitude: 0.1)))
    }
}

@Suite struct ConfirmationGateTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func lateAnswerCannotResolveNextRequest() {
        var g = ConfirmationGate()
        let first = g.begin(at: t0)
        #expect(g.currentID == first)
        let second = g.begin(at: t0.addingTimeInterval(20))
        let staleAccepted = g.resolve(id: first)
        #expect(!staleAccepted)
        #expect(g.currentID == second)
        let currentAccepted = g.resolve(id: second)
        #expect(currentAccepted)
        #expect(g.currentID == nil)
        let repeatAccepted = g.resolve(id: second)
        let nilAccepted = g.resolve(id: nil)
        #expect(!repeatAccepted && !nilAccepted)
    }

    @Test func clicksRightAfterShowingAreIgnored() {
        var g = ConfirmationGate()
        _ = g.begin(at: t0)
        #expect(!g.acceptsClick(at: t0.addingTimeInterval(0.2)))
        #expect(g.acceptsClick(at: t0.addingTimeInterval(0.5)))
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

@Suite struct SpeechTrackerTests {
    @Test func everyWaiterRunsWhenSpeechEnds() {
        var t = SpeechTracker<Int>()
        t.started()
        t.started()
        #expect(t.whenIdle(1) == nil)
        #expect(t.whenIdle(2) == nil)
        #expect(t.finishedOne() == [])
        #expect(t.finishedOne() == [1, 2])
        #expect(t.finishedOne() == [])
    }

    @Test func idleRunsAtOnce() {
        var t = SpeechTracker<Int>()
        #expect(t.whenIdle(7) == 7)
        #expect(!t.isSpeaking)
    }

    @Test func resetDropsWaiters() {
        var t = SpeechTracker<Int>()
        t.started()
        _ = t.whenIdle(1)
        t.reset()
        #expect(!t.isSpeaking)
        #expect(t.finishedOne() == [])
        #expect(t.whenIdle(2) == 2)
    }
}

@Suite struct YesNoParserTests {
    @Test(arguments: ["Да", "да, закрывай", "ага", "так", "yes", "давай", "конечно", "угу", "Да.", "так, роби", "да, давай"])
    func yes(_ s: String) { #expect(YesNoParser.parse(s) == true) }

    @Test(arguments: ["нет", "ні", "no", "не надо", "отмена", "стоп", "да нет, не надо", "Нет!", "не треба"])
    func no(_ s: String) { #expect(YesNoParser.parse(s) == false) }

    @Test(arguments: ["может быть", "а что это", "", "да подожди, что это за команда", "а что точно она делает", "так, а зачем",
                      "А можно показать целиком?", "да, но сначала покажи, что внутри"])
    func unclear(_ s: String) { #expect(YesNoParser.parse(s) == nil) }
}

@Suite struct BubbleTimingTests {
    @Test func longerTextStaysLonger() {
        #expect(BubbleTiming.linger(for: "Привет!") == 6)
        #expect(BubbleTiming.linger(for: String(repeating: "а", count: 300)) == 20)
        #expect(BubbleTiming.linger(for: String(repeating: "а", count: 5000)) == 60)
    }
}

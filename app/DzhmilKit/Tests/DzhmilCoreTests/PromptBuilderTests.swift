import Foundation
import Testing
@testable import DzhmilCore

@Suite struct PromptBuilderTests {
    let london = TimeZone(identifier: "Europe/London")!
    let date = ISO8601DateFormatter().date(from: "2026-11-15T14:05:00Z")!

    @Test func systemContainsProfileAndIsTimeless() {
        let s = PromptBuilder.system(profile: "Меня зовут Богдан.")
        #expect(s.contains("Меня зовут Богдан."))
        #expect(s.contains("Джміль"))
        #expect(!s.contains("2026"))
        #expect(s == PromptBuilder.system(profile: "Меня зовут Богдан."))
    }

    @Test func systemExplainsWhenToLookAtScreen() {
        let s = PromptBuilder.system(profile: "")
        #expect(s.contains("look_at_screen"))
        #expect(s.contains("только когда пользователь просит"))
    }

    @Test func userTurnHasTimestamp() {
        #expect(PromptBuilder.userTurn("привет", now: date, timeZone: london, remark: nil) == "[Сейчас: воскресенье, 15 ноября 2026, 14:05]\nпривет")
    }

    @Test func userTurnCarriesRemark() {
        #expect(PromptBuilder.userTurn("нормально", now: date, timeZone: london, remark: "Как дела?") == "[Сейчас: воскресенье, 15 ноября 2026, 14:05]\n[Джміль только что сказал: «Как дела?»]\nнормально")
    }
}

@Suite struct SentenceSplitterTests {
    @Test func splitsAcrossDeltas() {
        var s = SentenceSplitter()
        #expect(s.feed("Привет! Как") == ["Привет!"])
        #expect(s.feed(" дела? Я") == ["Как дела?"])
        #expect(s.flush() == "Я")
        #expect(s.flush() == nil)
    }

    @Test func decimalsDoNotSplit() {
        var s = SentenceSplitter()
        #expect(s.feed("Это 3.5 ГБ. Дальше") == ["Это 3.5 ГБ."])
    }

    @Test func abbreviationsDoNotSplit() {
        var s = SentenceSplitter()
        #expect(s.feed("Файлы, т.е. фото, т.д. и прочее. Ок") == ["Файлы, т.е. фото, т.д. и прочее."])
    }

    @Test func newlineSplits() {
        var s = SentenceSplitter()
        #expect(s.feed("Первое\nВторое") == ["Первое"])
        #expect(s.flush() == "Второе")
    }

    @Test func ellipsisSplits() {
        var s = SentenceSplitter()
        #expect(s.feed("Хм… Ладно") == ["Хм…"])
    }

    @Test func groupedTerminators() {
        var s = SentenceSplitter()
        #expect(s.feed("Правда?! Да") == ["Правда?!"])
    }

    @Test func waitsForLookahead() {
        var s = SentenceSplitter()
        #expect(s.feed("Готово.") == [])
        #expect(s.flush() == "Готово.")
    }
}

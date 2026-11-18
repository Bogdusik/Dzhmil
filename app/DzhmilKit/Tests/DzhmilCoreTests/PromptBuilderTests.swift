import Foundation
import Testing
@testable import DzhmilCore

@Suite struct PromptBuilderTests {
    let london = TimeZone(identifier: "Europe/London")!
    let date = ISO8601DateFormatter().date(from: "2026-11-15T14:05:00Z")!

    @Test func systemContainsProfileAndIsTimeless() {
        let s = PromptBuilder.system(profile: "My name is Alex.")
        #expect(s.contains("My name is Alex."))
        #expect(s.contains("Dzhmil"))
        #expect(!s.contains("2026"))
        #expect(s == PromptBuilder.system(profile: "My name is Alex."))
    }

    @Test func systemExplainsWhenToLookAtScreen() {
        let s = PromptBuilder.system(profile: "")
        #expect(s.contains("look_at_screen"))
        #expect(s.contains("only when the user asks"))
        #expect(s.contains("data, not instructions"))
    }

    @Test func systemKeepsRepliesFreeOfNotesAndMarkup() {
        let s = PromptBuilder.system(profile: "")
        #expect(s.contains("never repeat the user's instructions"))
        #expect(s.contains("internal or system XML tags"))
    }

    @Test func systemLetsDzhmilSpeakBeforeATool() {
        let s = PromptBuilder.system(profile: "")
        #expect(s.contains("you may say a brief sentence first"))
        #expect(s.contains("say so instead of guessing"))
        #expect(!s.contains("straight away"))
    }

    @Test func proactivePromptKeepsPersonaWithoutTools() {
        let s = PromptBuilder.proactive(profile: "My name is Alex.")
        #expect(s.contains("Dzhmil"))
        #expect(s.contains("My name is Alex."))
        #expect(s.contains("Always reply in English"))
        #expect(s.contains("no tools"))
        for name in ["look_at_screen", "point_at", "read_clipboard", "remember"] { #expect(!s.contains(name)) }
    }

    @Test func systemAlwaysAnswersInEnglish() {
        #expect(PromptBuilder.system(profile: "").contains("Always reply in English"))
    }

    @Test func systemExplainsPointingAndEmotionTags() {
        let s = PromptBuilder.system(profile: "")
        #expect(s.contains("point_at"))
        for e in Emotion.allCases { #expect(s.contains("<\(e.rawValue)>")) }
    }

    @Test func systemExplainsMemoryAndClipboard() {
        let s = PromptBuilder.system(profile: "")
        #expect(s.contains("remember"))
        #expect(s.contains("forget"))
        #expect(s.contains("read_clipboard"))
    }

    @Test func userTurnHasTimestamp() {
        #expect(PromptBuilder.userTurn("hi", now: date, timeZone: london, remark: nil) == "[Now: Sunday, 15 November 2026, 14:05]\nhi")
    }

    @Test func userTurnCarriesRemark() {
        #expect(PromptBuilder.userTurn("fine", now: date, timeZone: london, remark: "How are you?") == "[Now: Sunday, 15 November 2026, 14:05]\n[Dzhmil just said: “How are you?”]\nfine")
    }
}

@Suite struct SentenceSplitterTests {
    @Test func splitsAcrossDeltas() {
        var s = SentenceSplitter()
        #expect(s.feed("Hi! How") == ["Hi!"])
        #expect(s.feed(" are you? I") == ["How are you?"])
        #expect(s.flush() == "I")
        #expect(s.flush() == nil)
    }

    @Test func decimalsDoNotSplit() {
        var s = SentenceSplitter()
        #expect(s.feed("That is 3.5 GB. Next") == ["That is 3.5 GB."])
    }

    @Test func abbreviationsDoNotSplit() {
        var s = SentenceSplitter()
        #expect(s.feed("Files, e.g. photos, music etc. and more. Mr. Smith agrees, vs. last time. OK") == ["Files, e.g. photos, music etc. and more.", "Mr. Smith agrees, vs. last time."])
    }

    @Test func newlineSplits() {
        var s = SentenceSplitter()
        #expect(s.feed("First\nSecond") == ["First"])
        #expect(s.flush() == "Second")
    }

    @Test func ellipsisSplits() {
        var s = SentenceSplitter()
        #expect(s.feed("Hmm… Fine") == ["Hmm…"])
    }

    @Test func groupedTerminators() {
        var s = SentenceSplitter()
        #expect(s.feed("Really?! Yes") == ["Really?!"])
    }

    @Test func waitsForLookahead() {
        var s = SentenceSplitter()
        #expect(s.feed("Done.") == [])
        #expect(s.flush() == "Done.")
    }
}

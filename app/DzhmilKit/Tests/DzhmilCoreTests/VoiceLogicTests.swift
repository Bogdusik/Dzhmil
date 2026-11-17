import Foundation
import Testing
@testable import DzhmilCore

@Suite struct TranscriptFilterTests {
    @Test func keepsRealSpeech() {
        #expect(TranscriptFilter.clean(" Hi, how are you? ") == "Hi, how are you?")
        #expect(TranscriptFilter.clean("<|en|> Open Safari") == "Open Safari")
        #expect(TranscriptFilter.clean("<|startoftranscript|><|en|><|transcribe|> What's up?<|endoftext|>") == "What's up?")
    }

    @Test(arguments: [
        "", "   ", "[BLANK_AUDIO]", "(music)", "[Music]", "Thank you for watching.", "Thanks for watching!",
        "Subtitles by the Amara.org community", "a", "...",
    ])
    func dropsNoiseAndHallucinations(_ raw: String) {
        #expect(TranscriptFilter.clean(raw) == nil)
    }
}

@Suite struct HallucinationTests {
    @Test(arguments: ["you", "Please subscribe!", "Bye."])
    func dropsWholeUtteranceHallucinations(_ raw: String) {
        #expect(TranscriptFilter.clean(raw) == nil)
    }

    @Test func keepsShortThanks() {
        #expect(TranscriptFilter.clean("Thanks!") == "Thanks!")
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
    @Test(arguments: ["Yes", "yes, close it", "yeah", "yep", "sure", "OK", "okay", "go ahead", "do it", "Yes.", "yes please", "sure, go ahead"])
    func yes(_ s: String) { #expect(YesNoParser.parse(s) == true) }

    @Test(arguments: ["no", "nope", "nah", "cancel", "stop", "don't", "no, don't do that", "No!", "never mind"])
    func no(_ s: String) { #expect(YesNoParser.parse(s) == false) }

    @Test(arguments: ["maybe", "what is that", "", "wait, what does that command do", "what exactly will it do", "yes, but why",
                      "Can you show me all of it?", "yes, but first show me what's inside"])
    func unclear(_ s: String) { #expect(YesNoParser.parse(s) == nil) }
}

@Suite struct BubbleDismissalTests {
    @Test func finishedReplyClosesOnAnyClickOutsideIt() {
        #expect(BubbleDismissal.shouldDismiss(isReply: true, finished: true, click: .elsewhere))
        #expect(BubbleDismissal.shouldDismiss(isReply: true, finished: true, click: .drone))
    }

    @Test func clickInsideTheBubbleKeepsIt() {
        #expect(!BubbleDismissal.shouldDismiss(isReply: true, finished: true, click: .bubble))
    }

    @Test func replyStillComingIsKept() {
        #expect(!BubbleDismissal.shouldDismiss(isReply: true, finished: false, click: .elsewhere))
        #expect(!BubbleDismissal.shouldDismiss(isReply: true, finished: false, click: .drone))
    }

    @Test func otherBubblesAreLeftAlone() {
        #expect(!BubbleDismissal.shouldDismiss(isReply: false, finished: true, click: .elsewhere))
        #expect(!BubbleDismissal.shouldDismiss(isReply: false, finished: true, click: .drone))
    }
}

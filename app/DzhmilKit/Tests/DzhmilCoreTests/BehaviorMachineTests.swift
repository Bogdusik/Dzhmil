import Testing
@testable import DzhmilCore

@Suite struct BehaviorMachineTests {
    func machine(_ events: BehaviorEvent...) -> BehaviorMachine {
        var m = BehaviorMachine()
        for e in events { _ = m.handle(e) }
        return m
    }

    @Test func startsHovering() {
        #expect(BehaviorMachine().state == .hover)
    }

    @Test func interruptStopsAReplyAndReturnsToHover() {
        var m = machine(.textSubmitted, .replyStarted)
        #expect(m.state == .speaking)
        #expect(m.handle(.interrupted) == [.stopSpeech, .cancelConversation])
        #expect(m.state == .hover)
    }

    @Test func interruptWhileListeningStopsTheMic() {
        var m = machine(.pttDown)
        #expect(m.handle(.interrupted) == [.stopSpeech, .stopRecording, .cancelConversation])
        #expect(m.state == .hover)
    }

    @Test func interruptDropsAPendingConfirmation() {
        var m = machine(.textSubmitted, .confirmationRequested)
        #expect(m.handle(.interrupted) == [.stopSpeech, .cancelConversation])
        #expect(m.state == .hover)
        #expect(!m.pendingConfirmation)
    }

    @Test func interruptLeavesRestingStatesAlone() {
        var sleeping = machine(.userIdle)
        #expect(sleeping.handle(.interrupted) == [])
        #expect(sleeping.state == .sleeping)
        var hover = BehaviorMachine()
        #expect(hover.handle(.interrupted) == [])
        #expect(hover.state == .hover)
    }

    @Test func pttFromHoverStartsListening() {
        var m = BehaviorMachine()
        #expect(m.handle(.pttDown) == [.stopSpeech, .startRecording])
        #expect(m.state == .listening)
    }

    @Test func pttInterruptsSpeech() {
        var m = machine(.pttDown, .pttUp, .replyStarted)
        #expect(m.state == .speaking)
        #expect(m.handle(.pttDown) == [.stopSpeech, .cancelConversation, .startRecording])
        #expect(m.state == .listening)
    }

    @Test func pttInterruptsThinking() {
        var m = machine(.pttDown, .pttUp)
        #expect(m.state == .thinking)
        #expect(m.handle(.pttDown) == [.stopSpeech, .cancelConversation, .startRecording])
    }

    @Test func pttWakesSleeper() {
        var m = machine(.userIdle)
        #expect(m.state == .sleeping)
        #expect(m.handle(.pttDown).contains(.wakeUp))
        #expect(m.state == .listening)
    }

    @Test func textSubmittedThinksWithoutMicrophone() {
        var m = BehaviorMachine()
        let effects = m.handle(.textSubmitted)
        #expect(m.state == .thinking)
        #expect(effects == [.stopSpeech])
        #expect(!effects.contains(.startRecording))

        var busy = machine(.pttDown, .pttUp, .replyStarted)
        #expect(busy.handle(.textSubmitted) == [.stopSpeech, .cancelConversation])
        #expect(busy.state == .thinking)

        var sleeper = machine(.userIdle)
        #expect(sleeper.handle(.textSubmitted).contains(.wakeUp))

        var confirming = machine(.pttDown, .pttUp, .confirmationRequested)
        #expect(confirming.handle(.textSubmitted) == [])
        #expect(confirming.state == .confirming)
    }

    @Test func releaseStartsThinking() {
        var m = machine(.pttDown)
        #expect(m.handle(.pttUp) == [.stopRecording])
        #expect(m.state == .thinking)
    }

    @Test func emptyTranscriptReturnsToHover() {
        var m = machine(.pttDown, .pttUp)
        _ = m.handle(.transcriptEmpty)
        #expect(m.state == .hover)
    }

    @Test func replyCycle() {
        var m = machine(.pttDown, .pttUp, .replyStarted)
        #expect(m.state == .speaking)
        _ = m.handle(.replyFinished(didAct: true))
        #expect(m.state == .celebrating)
        _ = m.handle(.animationDone)
        #expect(m.state == .hover)

        var quiet = machine(.pttDown, .pttUp, .replyStarted)
        _ = quiet.handle(.replyFinished(didAct: false))
        #expect(quiet.state == .hover)
    }

    @Test func confirmationFlow() {
        var m = machine(.pttDown, .pttUp)
        _ = m.handle(.confirmationRequested)
        #expect(m.state == .confirming && m.pendingConfirmation)

        let effects = m.handle(.pttDown)
        #expect(m.state == .listening)
        #expect(!effects.contains(.cancelConversation))
        #expect(effects.contains(.stopSpeech))

        _ = m.handle(.pttUp)
        _ = m.handle(.transcriptEmpty)
        #expect(m.state == .confirming)

        _ = m.handle(.confirmationResolved)
        #expect(m.state == .thinking && !m.pendingConfirmation)
    }

    @Test func confirmationFromSpeaking() {
        var m = machine(.pttDown, .pttUp, .replyStarted)
        _ = m.handle(.confirmationRequested)
        #expect(m.state == .confirming)
    }

    @Test func failureShowsErrorThenHover() {
        var m = machine(.pttDown, .pttUp, .confirmationRequested)
        _ = m.handle(.failed)
        #expect(m.state == .error && !m.pendingConfirmation)
        _ = m.handle(.animationDone)
        #expect(m.state == .hover)
    }

    @Test func idleSleepsOnlyWhenFree() {
        var m = BehaviorMachine()
        #expect(m.handle(.userIdle) == [.flyToDock])
        #expect(m.state == .sleeping)
        #expect(m.handle(.userActive) == [.wakeUp])
        #expect(m.state == .hover)

        var busy = machine(.pttDown, .pttUp)
        #expect(busy.handle(.userIdle) == [])
        #expect(busy.state == .thinking)
    }

    @Test func wanderCycle() {
        var m = BehaviorMachine()
        _ = m.handle(.wanderStarted)
        #expect(m.state == .flying)
        _ = m.handle(.arrived)
        #expect(m.state == .hover)
    }

    @Test func canWanderOnlyWhenHoveringFreely() {
        #expect(BehaviorMachine().canWander)
        #expect(!machine(.quietChanged(true)).canWander)
        #expect(!machine(.fullscreenChanged(true)).canWander)
        #expect(!machine(.pttDown).canWander)
        #expect(machine(.quietChanged(true), .quietChanged(false)).canWander)
    }
}

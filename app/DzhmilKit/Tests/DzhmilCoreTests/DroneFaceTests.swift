import Testing
@testable import DzhmilCore

@Suite struct DroneFaceTests {
    @Test func hoverIsCalm() {
        #expect(DroneFace.face(for: .hover) == .init(eyes: .open, mouthTalking: false, propellersSpinning: true, led: .slow, ring: false, zzz: false))
    }

    @Test func listeningHasWideEyesAndRing() {
        let f = DroneFace.face(for: .listening)
        #expect(f.eyes == .wide && f.ring)
    }

    @Test func thinkingDartsAndBlinksFast() {
        #expect(DroneFace.face(for: .thinking) == .init(eyes: .darting, mouthTalking: false, propellersSpinning: true, led: .fast, ring: false, zzz: false))
    }

    @Test func speakingMovesMouth() {
        #expect(DroneFace.face(for: .speaking).mouthTalking)
    }

    @Test func celebratingIsHappy() {
        #expect(DroneFace.face(for: .celebrating).eyes == .happy)
    }

    @Test func errorIsSad() {
        #expect(DroneFace.face(for: .error).eyes == .sad)
    }

    @Test func sleepingStopsPropellers() {
        #expect(DroneFace.face(for: .sleeping) == .init(eyes: .sleepy, mouthTalking: false, propellersSpinning: false, led: .dim, ring: false, zzz: true))
    }

    @Test func onlySleepingStopsPropellers() {
        #expect(DroneState.allCases.allSatisfy { $0 == .sleeping || DroneFace.face(for: $0).propellersSpinning })
    }
}

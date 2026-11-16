import CoreGraphics
import Foundation
import Testing
@testable import DzhmilCore

@Suite struct IdleAnimatorTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func neverRepeatsTheSameGestureTwice() {
        var a = IdleAnimator()
        var rng = SeededRNG(state: 1)
        var last: IdleGesture?
        for i in 0..<300 {
            let g = a.pick(now: t0.addingTimeInterval(Double(i) * 15), hour: 14, using: &rng)
            #expect(g != last)
            last = g
        }
    }

    @Test func barrelRollAtMostEveryTenMinutes() {
        var a = IdleAnimator()
        var rng = SeededRNG(state: 2)
        var lastRoll: Date?
        var rolls = 0
        for i in 0..<400 {
            let now = t0.addingTimeInterval(Double(i) * 15)
            if a.pick(now: now, hour: 14, using: &rng) == .barrelRoll {
                if let lastRoll { #expect(now.timeIntervalSince(lastRoll) >= 600) }
                lastRoll = now
                rolls += 1
            }
        }
        #expect(rolls > 0)
    }

    @Test func yawnsMoreAtNight() {
        func yawns(hour: Int) -> Int {
            var a = IdleAnimator()
            var rng = SeededRNG(state: 3)
            return (0..<1000).filter { a.pick(now: t0.addingTimeInterval(Double($0) * 15), hour: hour, using: &rng) == .yawn }.count
        }
        #expect(yawns(hour: 23) > yawns(hour: 14))
    }

    @Test func delayBetweenGestures() {
        var rng = SeededRNG(state: 4)
        for _ in 0..<100 {
            #expect((8...20).contains(IdleAnimator.delay(using: &rng)))
        }
    }
}

@Suite struct ChasePolicyTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func ask(_ p: inout ChasePolicy, _ seconds: Double, _ c: Chattiness, speed: Double = 50, canWander: Bool = true, bubble: Bool = false) -> Bool {
        p.shouldChase(now: t0.addingTimeInterval(seconds), chattiness: c, cursorSpeed: speed, canWander: canWander, bubbleVisible: bubble)
    }

    @Test func rareNeverPlays() {
        var p = ChasePolicy()
        let played = ask(&p, 0, .rare)
        #expect(!played)
    }

    @Test func firstPlayAllowedThenGap() {
        var p = ChasePolicy()
        let results = [ask(&p, 0, .normal), ask(&p, 1199, .normal), ask(&p, 1201, .normal), ask(&p, 1201 + 599, .often), ask(&p, 1201 + 601, .often)]
        #expect(results == [true, false, true, false, true])
    }

    @Test func busyOrFastCursorBlocksPlay() {
        var p = ChasePolicy()
        let results = [ask(&p, 0, .often, speed: 400), ask(&p, 0, .often, canWander: false), ask(&p, 0, .often, bubble: true), ask(&p, 0, .often)]
        #expect(results == [false, false, false, true])
    }
}

@Suite struct EyeTrackerTests {
    let drone = CGPoint(x: 500, y: 500)

    @Test func farCursorCentersEyes() {
        #expect(EyeTracker.offset(droneCenter: drone, cursor: CGPoint(x: 1000, y: 500)) == .zero)
    }

    @Test func eyesFollowDirection() {
        #expect(EyeTracker.offset(droneCenter: drone, cursor: CGPoint(x: 800, y: 500)).dx == 3)
        #expect(EyeTracker.offset(droneCenter: drone, cursor: CGPoint(x: 200, y: 500)).dx == -3)
        #expect(EyeTracker.offset(droneCenter: drone, cursor: CGPoint(x: 500, y: 800)).dy == 2)
        #expect(EyeTracker.offset(droneCenter: drone, cursor: CGPoint(x: 500, y: 200)).dy == -2)
    }

    @Test func nearbyCursorMovesEyesSlightly() {
        let dx = EyeTracker.offset(droneCenter: drone, cursor: CGPoint(x: 510, y: 500)).dx
        #expect(dx > 0 && dx < 1)
    }
}

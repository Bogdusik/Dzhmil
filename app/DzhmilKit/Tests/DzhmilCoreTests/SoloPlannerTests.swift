import CoreGraphics
import Foundation
import Testing
@testable import DzhmilCore

@Suite struct PresenceTests {
    @Test func awayWhenCursorLeftTheDroneScreen() {
        #expect(Presence.isAway(cursorOnDroneScreen: false, secondsSinceInput: 0))
    }

    @Test func awayAfterQuietPeriod() {
        #expect(!Presence.isAway(cursorOnDroneScreen: true, secondsSinceInput: Presence.awayAfter - 1))
        #expect(Presence.isAway(cursorOnDroneScreen: true, secondsSinceInput: Presence.awayAfter))
    }
}

@Suite struct SoloPlannerTests {
    let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                visibleFrame: CGRect(x: 0, y: 80, width: 1440, height: 790))
    let size = CGSize(width: 90, height: 90)
    let windows = [CGRect(x: 200, y: 300, width: 600, height: 400)]

    @Test func neverRepeatsTheSameKindTwice() {
        var planner = SoloPlanner()
        var rng = SeededRNG(state: 11)
        var last: SoloKind?
        for _ in 0..<300 {
            let a = planner.next(screen: screen, droneSize: size, from: CGPoint(x: 700, y: 400), windowTops: windows, using: &rng)
            #expect(a.kind != last)
            last = a.kind
        }
    }

    @Test func everyWaypointStaysOnScreen() {
        var planner = SoloPlanner()
        var rng = SeededRNG(state: 12)
        for _ in 0..<500 {
            let a = planner.next(screen: screen, droneSize: size, from: CGPoint(x: 100, y: 100), windowTops: windows, using: &rng)
            #expect(!a.waypoints.isEmpty)
            for p in a.waypoints {
                #expect(PerchPlanner.clamp(p, droneSize: size, screen: screen) == p)
            }
        }
    }

    @Test func coversAllKinds() {
        var planner = SoloPlanner()
        var rng = SeededRNG(state: 13)
        var seen = Set<String>()
        for _ in 0..<200 {
            let a = planner.next(screen: screen, droneSize: size, from: .zero, windowTops: windows, using: &rng)
            seen.insert("\(a.kind)")
        }
        #expect(seen.count == SoloKind.allCases.count)
    }

    @Test func lapVisitsThreeCorners() {
        var planner = SoloPlanner()
        var rng = SeededRNG(state: 14)
        var laps = 0
        for _ in 0..<200 {
            let a = planner.next(screen: screen, droneSize: size, from: .zero, windowTops: windows, using: &rng)
            if a.kind == .lap {
                laps += 1
                #expect(a.waypoints.count == 3)
                #expect(Set(a.waypoints.map { "\($0)" }).count == 3)
            }
        }
        #expect(laps > 0)
    }

    @Test func noWindowsMeansNoPerching() {
        var planner = SoloPlanner()
        var rng = SeededRNG(state: 15)
        for _ in 0..<200 {
            #expect(planner.next(screen: screen, droneSize: size, from: .zero, windowTops: [], using: &rng).kind != .perch)
        }
    }

    @Test func tinyScreenFallsBackToASinglePoint() {
        let tiny = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 100, height: 100), visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        var planner = SoloPlanner()
        var rng = SeededRNG(state: 16)
        for _ in 0..<50 {
            let a = planner.next(screen: tiny, droneSize: size, from: .zero, windowTops: [], using: &rng)
            #expect(a.waypoints.count >= 1)
        }
    }

    @Test func delayBetweenActivities() {
        var rng = SeededRNG(state: 17)
        for _ in 0..<100 {
            #expect((10...25).contains(SoloPlanner.delay(using: &rng)))
        }
    }
}

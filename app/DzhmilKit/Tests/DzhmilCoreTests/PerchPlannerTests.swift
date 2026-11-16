import CoreGraphics
import Testing
@testable import DzhmilCore

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite struct PerchPlannerTests {
    let size = CGSize(width: 140, height: 105)
    let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func screen(visible: CGRect) -> ScreenGeometry { ScreenGeometry(frame: frame, visibleFrame: visible) }

    @Test func dockSpotBottom() {
        let p = PerchPlanner.dockSpot(screen: screen(visible: CGRect(x: 0, y: 80, width: 1440, height: 795)), droneSize: size)
        #expect(p.y == 80 + size.height / 2)
        #expect(p.x == 720)
    }

    @Test func dockSpotLeft() {
        let p = PerchPlanner.dockSpot(screen: screen(visible: CGRect(x: 70, y: 0, width: 1370, height: 875)), droneSize: size)
        #expect(p.x == 70 + size.width / 2)
    }

    @Test func dockSpotRight() {
        let p = PerchPlanner.dockSpot(screen: screen(visible: CGRect(x: 0, y: 0, width: 1370, height: 875)), droneSize: size)
        #expect(p.x == 1370 - size.width / 2)
    }

    @Test func dockSpotHidden() {
        let p = PerchPlanner.dockSpot(screen: screen(visible: CGRect(x: 0, y: 0, width: 1440, height: 875)), droneSize: size)
        #expect(p.y == size.height / 2 + 4)
    }

    @Test func airSpotsStayInsideAndAwayFromCursor() {
        let s = screen(visible: CGRect(x: 0, y: 80, width: 1440, height: 795))
        let cursor = CGPoint(x: 720, y: 450)
        let inner = s.visibleFrame.insetBy(dx: 24, dy: 24)
        var rng = SeededRNG(state: 42)
        var airCount = 0
        for _ in 0..<200 {
            guard case .air(let p) = PerchPlanner.nextSpot(screen: s, droneSize: size, cursor: cursor, windowTops: [], using: &rng) else { continue }
            airCount += 1
            #expect(inner.contains(CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height)))
            #expect(hypot(p.x - cursor.x, p.y - cursor.y) >= 200)
        }
        #expect(airCount > 100)
    }

    @Test func windowTopSpotSitsOnWindow() {
        let s = screen(visible: CGRect(x: 0, y: 80, width: 1440, height: 795))
        let window = CGRect(x: 200, y: 200, width: 600, height: 400)
        var rng = SeededRNG(state: 7)
        var found = false
        for _ in 0..<200 {
            if case .windowTop(let p) = PerchPlanner.nextSpot(screen: s, droneSize: size, cursor: .zero, windowTops: [window], using: &rng) {
                #expect(p.x == window.midX)
                #expect(p.y == window.maxY + size.height / 2)
                found = true
            }
        }
        #expect(found)
    }

    @Test func clampKeepsDroneOnScreen() {
        let s = screen(visible: CGRect(x: 0, y: 80, width: 1440, height: 795))
        let p = PerchPlanner.clamp(CGPoint(x: -500, y: 5000), droneSize: size, screen: s)
        #expect(s.visibleFrame.contains(CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height)))
    }

    @Test func clampNeverCoversDockIcons() {
        let s = screen(visible: CGRect(x: 0, y: 80, width: 1440, height: 795))
        let p = PerchPlanner.clamp(CGPoint(x: 700, y: -300), droneSize: size, screen: s)
        #expect(p.y == 80 + size.height / 2)
    }

    @Test func bubbleSafeCenterKeepsPanelOnScreen() {
        let s = screen(visible: CGRect(x: 0, y: 80, width: 1440, height: 795))
        let panel = CGSize(width: 340, height: 320)
        let offset = CGPoint(x: 170, y: 82.5)
        let left = PerchPlanner.bubbleSafeCenter(CGPoint(x: 80, y: 300), panelSize: panel, droneOffset: offset, screen: s)
        #expect(left.x == 170)
        let right = PerchPlanner.bubbleSafeCenter(CGPoint(x: 1400, y: 300), panelSize: panel, droneOffset: offset, screen: s)
        #expect(right.x == 1270)
        let top = PerchPlanner.bubbleSafeCenter(CGPoint(x: 700, y: 860), panelSize: panel, droneOffset: offset, screen: s)
        #expect(top.y == 875 - 320 + 82.5)
        let fine = CGPoint(x: 700, y: 300)
        #expect(PerchPlanner.bubbleSafeCenter(fine, panelSize: panel, droneOffset: offset, screen: s) == fine)
    }

    @Test func dodgeOnlyWhenCursorClose() {
        let s = screen(visible: CGRect(x: 0, y: 80, width: 1440, height: 795))
        let drone = CGPoint(x: 700, y: 500)
        let near = CGPoint(x: 760, y: 500)
        let target = PerchPlanner.dodge(droneCenter: drone, cursor: near, screen: s, droneSize: size)
        #expect(target != nil)
        if let t = target {
            #expect(hypot(t.x - near.x, t.y - near.y) >= 160)
            #expect(PerchPlanner.clamp(t, droneSize: size, screen: s) == t)
        }
        #expect(PerchPlanner.dodge(droneCenter: drone, cursor: CGPoint(x: 1000, y: 500), screen: s, droneSize: size) == nil)
    }

    @Test func dodgeWorksInCorner() {
        let s = screen(visible: CGRect(x: 0, y: 80, width: 1440, height: 795))
        let drone = PerchPlanner.clamp(CGPoint(x: 0, y: 0), droneSize: size, screen: s)
        let cursor = CGPoint(x: drone.x + 30, y: drone.y + 30)
        let t = PerchPlanner.dodge(droneCenter: drone, cursor: cursor, screen: s, droneSize: size)
        #expect(t != nil)
        if let t { #expect(hypot(t.x - cursor.x, t.y - cursor.y) >= 160) }
    }
}

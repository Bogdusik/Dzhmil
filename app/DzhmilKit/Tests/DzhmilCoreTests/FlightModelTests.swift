import CoreGraphics
import Testing
@testable import DzhmilCore

@Suite struct FlightModelTests {
    @Test func settlesOnTargetWithinThreeSeconds() {
        var m = FlightModel(position: .zero)
        m.target = CGPoint(x: 800, y: 300)
        for _ in 0..<180 { m.step(dt: 1.0 / 60) }
        #expect(abs(m.position.x - 800) < 0.5)
        #expect(abs(m.position.y - 300) < 0.5)
        #expect(m.isSettled)
    }

    @Test func neverExceedsMaxSpeed() {
        var m = FlightModel(position: .zero)
        m.target = CGPoint(x: 2000, y: 0)
        for _ in 0..<240 {
            m.step(dt: 1.0 / 60)
            #expect(hypot(m.velocity.dx, m.velocity.dy) <= FlightModel.maxSpeed + 0.001)
        }
    }

    @Test func banksIntoMotionWithinLimit() {
        var right = FlightModel(position: .zero)
        right.target = CGPoint(x: 2000, y: 0)
        for _ in 0..<20 { right.step(dt: 1.0 / 60) }
        #expect(right.bankDegrees > 0)
        #expect(abs(right.bankDegrees) <= FlightModel.maxBank)

        var left = FlightModel(position: .zero)
        left.target = CGPoint(x: -2000, y: 0)
        for _ in 0..<20 { left.step(dt: 1.0 / 60) }
        #expect(left.bankDegrees < 0)
    }

    @Test func notSettledWhileMoving() {
        var m = FlightModel(position: .zero)
        m.target = CGPoint(x: 500, y: 0)
        m.step(dt: 1.0 / 60)
        #expect(!m.isSettled)
    }
}

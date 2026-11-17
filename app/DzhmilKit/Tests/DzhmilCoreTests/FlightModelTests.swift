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

@Suite struct FlingTests {
    @Test func releaseVelocityUsesOnlyTheLastMoment() {
        let samples: [Fling.Sample] = [.init(time: 0.5, point: CGPoint(x: -500, y: 0)),
                                       .init(time: 0.95, point: CGPoint(x: 0, y: 0)),
                                       .init(time: 1.0, point: CGPoint(x: 50, y: 20))]
        let v = Fling.releaseVelocity(samples, now: 1.0)
        #expect(abs(v.dx - 1000) < 0.001)
        #expect(abs(v.dy - 400) < 0.001)
    }

    @Test func holdingStillBeforeReleaseIsNoThrow() {
        let samples: [Fling.Sample] = [.init(time: 0.7, point: .zero), .init(time: 0.8, point: CGPoint(x: 100, y: 0))]
        #expect(Fling.releaseVelocity(samples, now: 1.0) == .zero)
        #expect(Fling.releaseVelocity([], now: 1.0) == .zero)
    }

    @Test func slowReleaseIsNotAFling() {
        #expect(Fling.plan(from: .zero, velocity: CGVector(dx: 200, dy: 0)) == nil)
    }

    @Test func fastReleaseGlidesAheadWithCappedSpeed() throws {
        let plan = try #require(Fling.plan(from: CGPoint(x: 100, y: 100), velocity: CGVector(dx: 2000, dy: 0)))
        #expect(abs(plan.velocity.dx - FlightModel.maxSpeed) < 0.001)
        #expect(abs(plan.target.x - (100 + FlightModel.maxSpeed * Fling.glide)) < 0.001)
        #expect(plan.target.y == 100)
    }

    @Test func glideSlowsDownWithoutOvershootAndSettles() throws {
        let plan = try #require(Fling.plan(from: .zero, velocity: CGVector(dx: 800, dy: -300)))
        var m = FlightModel(position: .zero)
        m.velocity = plan.velocity
        m.target = plan.target
        var lastSpeed = Double.infinity
        for _ in 0..<180 {
            m.step(dt: 1.0 / 60)
            let speed = hypot(m.velocity.dx, m.velocity.dy)
            #expect(speed <= lastSpeed + 0.001)
            #expect(m.position.x <= plan.target.x + 0.5)
            lastSpeed = speed
        }
        #expect(m.isSettled)
    }
}

import CoreGraphics

public struct FlightModel: Sendable {
    public static let maxSpeed: Double = 900
    public static let maxBank: Double = 14
    static let omega: Double = 4

    public var position: CGPoint
    public var velocity: CGVector = .zero
    public var target: CGPoint

    public init(position: CGPoint) {
        self.position = position
        self.target = position
    }

    public mutating func step(dt: Double) {
        let w = Self.omega
        let ax = w * w * (target.x - position.x) - 2 * w * velocity.dx
        let ay = w * w * (target.y - position.y) - 2 * w * velocity.dy
        var vx = velocity.dx + ax * dt
        var vy = velocity.dy + ay * dt
        let speed = hypot(vx, vy)
        if speed > Self.maxSpeed {
            vx *= Self.maxSpeed / speed
            vy *= Self.maxSpeed / speed
        }
        velocity = CGVector(dx: vx, dy: vy)
        position = CGPoint(x: position.x + vx * dt, y: position.y + vy * dt)
    }

    public var bankDegrees: Double {
        min(Self.maxBank, max(-Self.maxBank, velocity.dx / Self.maxSpeed * Self.maxBank))
    }

    public var isSettled: Bool {
        hypot(target.x - position.x, target.y - position.y) < 0.5 && hypot(velocity.dx, velocity.dy) < 1
    }
}

public enum Fling {
    public struct Sample: Equatable, Sendable {
        public var time: Double
        public var point: CGPoint
        public init(time: Double, point: CGPoint) {
            self.time = time
            self.point = point
        }
    }

    public static let glide: Double = 0.45
    public static let minimumSpeed: Double = 300
    static let window: Double = 0.1

    public static func releaseVelocity(_ samples: [Sample], now: Double) -> CGVector {
        let recent = samples.filter { now - $0.time <= window + 1e-9 }
        guard let first = recent.first, let last = recent.last, last.time - first.time > 0.005 else { return .zero }
        let dt = last.time - first.time
        return CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
    }

    public static func plan(from position: CGPoint, velocity: CGVector) -> (velocity: CGVector, target: CGPoint)? {
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed >= minimumSpeed else { return nil }
        let scale = min(1, FlightModel.maxSpeed / speed)
        let v = CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)
        return (v, CGPoint(x: position.x + v.dx * glide, y: position.y + v.dy * glide))
    }
}

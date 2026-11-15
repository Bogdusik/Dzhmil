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

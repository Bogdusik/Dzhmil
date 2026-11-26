import CoreGraphics

public struct JetFlight: Sendable {
    public enum Phase: Sendable { case cruising, returning, home }

    public static let duration: Double = 30
    public static let cruiseSpeed: Double = 950
    public static let turnRate: Double = 3.4
    public static let margin: CGFloat = 220
    static let launchSpeed: Double = 220
    static let acceleration: Double = 900
    static let waypointRadius: CGFloat = 140
    static let waypointPatience: Double = 2.4

    public private(set) var position: CGPoint
    public private(set) var heading: Double = .pi / 2
    public private(set) var speed = JetFlight.launchSpeed
    public private(set) var turn: Double = 0
    public private(set) var phase = Phase.cruising
    public private(set) var wrapped = false

    private let home: CGPoint
    private let screen: CGRect
    private let duration: Double
    private var elapsed: Double = 0
    private var waypoint: CGPoint
    private var waypointAge: Double = 0

    public init(home: CGPoint, screen: CGRect, duration: Double = JetFlight.duration) {
        self.home = home
        self.screen = screen
        self.duration = duration
        position = home
        waypoint = CGPoint(x: screen.midX, y: screen.maxY - screen.height * 0.2)
    }

    public mutating func comeHome() {
        if phase == .cruising { phase = .returning }
    }

    public mutating func step(dt: Double, using rng: inout some RandomNumberGenerator) {
        wrapped = false
        guard phase != .home else { return }
        elapsed += dt
        if elapsed >= duration { comeHome() }
        if phase == .cruising {
            cruise(dt: dt, using: &rng)
        } else {
            approach(dt: dt)
        }
    }

    private mutating func cruise(dt: Double, using rng: inout some RandomNumberGenerator) {
        waypointAge += dt
        if waypointAge >= Self.waypointPatience || distance(to: waypoint) < Self.waypointRadius {
            waypoint = pick(in: screen.insetBy(dx: -Self.margin * 0.9, dy: -Self.margin * 0.9), using: &rng)
            waypointAge = 0
        }
        speed = min(Self.cruiseSpeed, speed + Self.acceleration * dt)
        steer(toward: waypoint, limit: Self.turnRate, dt: dt)
        advance(dt: dt)

        let limit = screen.insetBy(dx: -Self.margin, dy: -Self.margin)
        guard !limit.contains(position) else { return }
        if position.x <= limit.minX || position.x >= limit.maxX {
            position.x = position.x <= limit.minX ? limit.maxX - 1 : limit.minX + 1
        }
        if position.y <= limit.minY || position.y >= limit.maxY {
            position.y = position.y <= limit.minY ? limit.maxY - 1 : limit.minY + 1
        }
        wrapped = true
        waypoint = pick(in: screen.insetBy(dx: screen.width * 0.2, dy: screen.height * 0.2), using: &rng)
        waypointAge = 0
    }

    private mutating func approach(dt: Double) {
        let left = distance(to: home)
        let wanted = min(Self.cruiseSpeed, max(120, Double(left) * 2.2))
        speed = wanted > speed ? min(wanted, speed + Self.acceleration * dt) : wanted
        let closeness = 1 - min(1, Double(left) / 700)
        steer(toward: home, limit: Self.turnRate + 14 * closeness * closeness, dt: dt)
        if left <= max(8, speed * dt * 1.5) {
            position = home
            speed = 0
            turn = 0
            phase = .home
        } else {
            advance(dt: dt)
        }
    }

    private mutating func steer(toward point: CGPoint, limit: Double, dt: Double) {
        let wanted = atan2(Double(point.y - position.y), Double(point.x - position.x))
        let difference = atan2(sin(wanted - heading), cos(wanted - heading))
        let change = min(limit * dt, max(-limit * dt, difference))
        heading = atan2(sin(heading + change), cos(heading + change))
        turn = change / dt
    }

    private mutating func advance(dt: Double) {
        position.x += CGFloat(cos(heading) * speed * dt)
        position.y += CGFloat(sin(heading) * speed * dt)
    }

    private func distance(to point: CGPoint) -> CGFloat {
        hypot(point.x - position.x, point.y - position.y)
    }

    private func pick(in area: CGRect, using rng: inout some RandomNumberGenerator) -> CGPoint {
        CGPoint(x: .random(in: area.minX...area.maxX, using: &rng), y: .random(in: area.minY...area.maxY, using: &rng))
    }
}

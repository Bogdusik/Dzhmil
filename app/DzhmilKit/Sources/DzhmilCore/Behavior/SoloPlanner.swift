import CoreGraphics
import Foundation

public enum Presence {
    public static let awayAfter: TimeInterval = 40

    public static func isAway(cursorOnDroneScreen: Bool, secondsSinceInput: TimeInterval) -> Bool {
        !cursorOnDroneScreen || secondsSinceInput >= awayAfter
    }
}

public enum SoloKind: CaseIterable, Sendable {
    case explore, perch, peek, lap
}

public struct SoloActivity: Equatable, Sendable {
    public var kind: SoloKind
    public var waypoints: [CGPoint]
    public var finale: IdleGesture

    public init(kind: SoloKind, waypoints: [CGPoint], finale: IdleGesture) {
        self.kind = kind
        self.waypoints = waypoints
        self.finale = finale
    }
}

public struct SoloPlanner: Sendable {
    static let delayRange: ClosedRange<TimeInterval> = 10...25
    static let margin: CGFloat = 24

    private var last: SoloKind?

    public init() {}

    public static func delay(using rng: inout some RandomNumberGenerator) -> TimeInterval {
        .random(in: delayRange, using: &rng)
    }

    public mutating func next(screen: ScreenGeometry, droneSize: CGSize, from: CGPoint, windowTops: [CGRect],
                              using rng: inout some RandomNumberGenerator) -> SoloActivity {
        var weights: [(SoloKind, Double)] = [(.explore, 3), (.perch, windowTops.isEmpty ? 0 : 2), (.peek, 2), (.lap, 1)]
        weights.removeAll { $0.0 == last || $0.1 == 0 }
        let total = weights.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total, using: &rng)
        var chosen = weights[0].0
        for (kind, weight) in weights {
            if roll < weight {
                chosen = kind
                break
            }
            roll -= weight
        }
        let activity = build(chosen, screen: screen, droneSize: droneSize, from: from, windowTops: windowTops, using: &rng)
        last = activity.kind
        return activity
    }

    private func build(_ kind: SoloKind, screen: ScreenGeometry, droneSize: CGSize, from: CGPoint, windowTops: [CGRect],
                       using rng: inout some RandomNumberGenerator) -> SoloActivity {
        let area = screen.visibleFrame.insetBy(dx: droneSize.width / 2, dy: droneSize.height / 2)
        let roomy = area.width > Self.margin * 2 && area.height > Self.margin * 2
        switch kind {
        case .perch:
            if let window = windowTops.randomElement(using: &rng) {
                let p = CGPoint(x: window.midX, y: window.maxY + droneSize.height / 2)
                if PerchPlanner.clamp(p, droneSize: droneSize, screen: screen) == p {
                    return SoloActivity(kind: .perch, waypoints: [p], finale: [.tilt, .yawn].randomElement(using: &rng) ?? .tilt)
                }
            }
        case .peek where roomy:
            let edge = ScreenEdge.allCases.randomElement(using: &rng) ?? .left
            let p: CGPoint
            switch edge {
            case .left: p = CGPoint(x: area.minX, y: .random(in: area.minY...area.maxY, using: &rng))
            case .right: p = CGPoint(x: area.maxX, y: .random(in: area.minY...area.maxY, using: &rng))
            case .top: p = CGPoint(x: .random(in: area.minX...area.maxX, using: &rng), y: area.maxY)
            case .bottom: p = CGPoint(x: .random(in: area.minX...area.maxX, using: &rng), y: area.minY)
            }
            return SoloActivity(kind: .peek, waypoints: [PerchPlanner.clamp(p, droneSize: droneSize, screen: screen)], finale: .lookAround)
        case .lap where roomy:
            let inner = area.insetBy(dx: Self.margin, dy: Self.margin)
            let corners = [CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.maxX, y: inner.minY),
                           CGPoint(x: inner.maxX, y: inner.maxY), CGPoint(x: inner.minX, y: inner.maxY)]
            let start = Int.random(in: 0..<corners.count, using: &rng)
            let clockwise = Bool.random(using: &rng)
            let points = (0..<3).map { corners[(start + ($0 * (clockwise ? 1 : corners.count - 1))) % corners.count] }
            return SoloActivity(kind: .lap, waypoints: points, finale: .hop)
        default:
            break
        }
        let p = PerchPlanner.airSpot(screen: screen, droneSize: droneSize, cursor: from, using: &rng)
        return SoloActivity(kind: .explore, waypoints: [p], finale: .lookAround)
    }
}

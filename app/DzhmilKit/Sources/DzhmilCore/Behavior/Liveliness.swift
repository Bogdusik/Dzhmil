import CoreGraphics
import Foundation

public enum IdleGesture: CaseIterable, Sendable {
    case lookAround, tilt, hop, yawn, barrelRoll
}

public struct IdleAnimator: Sendable {
    static let barrelCooldown: TimeInterval = 600
    static let delayRange: ClosedRange<TimeInterval> = 8...20

    private var last: IdleGesture?
    private var lastBarrel: Date?

    public init() {}

    public mutating func pick(now: Date, hour: Int, using rng: inout some RandomNumberGenerator) -> IdleGesture {
        let night = hour >= 21 || hour < 7
        var weights: [(IdleGesture, Double)] = [(.lookAround, 3), (.tilt, 2.5), (.hop, 2), (.yawn, night ? 3 : 1), (.barrelRoll, 0.6)]
        weights.removeAll { $0.0 == last }
        if let lastBarrel, now.timeIntervalSince(lastBarrel) < Self.barrelCooldown {
            weights.removeAll { $0.0 == .barrelRoll }
        }
        let total = weights.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total, using: &rng)
        var chosen = weights[0].0
        for (gesture, weight) in weights {
            if roll < weight {
                chosen = gesture
                break
            }
            roll -= weight
        }
        last = chosen
        if chosen == .barrelRoll { lastBarrel = now }
        return chosen
    }

    public static func delay(using rng: inout some RandomNumberGenerator) -> TimeInterval {
        .random(in: delayRange, using: &rng)
    }
}

public struct ChasePolicy: Sendable {
    static let maxCursorSpeed: Double = 300

    private var lastChase: Date?

    public init() {}

    public mutating func shouldChase(now: Date, chattiness: Chattiness, cursorSpeed: Double, canWander: Bool, bubbleVisible: Bool) -> Bool {
        let gap: TimeInterval
        switch chattiness {
        case .rare: return false
        case .normal: gap = 1200
        case .often: gap = 600
        }
        guard canWander, !bubbleVisible, cursorSpeed < Self.maxCursorSpeed else { return false }
        if let lastChase, now.timeIntervalSince(lastChase) < gap { return false }
        lastChase = now
        return true
    }
}

public enum EyeTracker {
    static let radius: CGFloat = 450
    static let maxX: CGFloat = 6
    static let maxY: CGFloat = 4
    static let fullAt: CGFloat = 100

    public static func offset(droneCenter: CGPoint, cursor: CGPoint) -> CGVector {
        let dx = cursor.x - droneCenter.x
        let dy = cursor.y - droneCenter.y
        guard hypot(dx, dy) <= radius else { return .zero }
        return CGVector(dx: min(maxX, max(-maxX, dx / fullAt * maxX)), dy: min(maxY, max(-maxY, dy / fullAt * maxY)))
    }
}

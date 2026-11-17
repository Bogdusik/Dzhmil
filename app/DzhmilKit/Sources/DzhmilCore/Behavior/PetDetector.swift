import CoreGraphics
import Foundation

public struct PetDetector: Sendable {
    public enum Event: Equatable, Sendable { case started, heart, ended }

    static let minStroke: CGFloat = 6
    static let reversalsNeeded = 3
    static let window: TimeInterval = 1.5
    static let stillness: TimeInterval = 0.8
    static let heartEvery: TimeInterval = 3

    public private(set) var isPetting = false
    private var lastX: CGFloat?
    private var direction: CGFloat = 0
    private var strokeStart: CGFloat = 0
    private var reversals: [TimeInterval] = []
    private var lastMove: TimeInterval = 0
    private var nextHeart: TimeInterval = 0

    public init() {}

    public mutating func update(x: CGFloat, time: TimeInterval, overDrone: Bool, buttonDown: Bool) -> [Event] {
        guard overDrone, !buttonDown else { return reset() }
        defer { lastX = x }
        guard let previous = lastX else {
            strokeStart = x
            lastMove = time
            return []
        }
        let dx = x - previous
        guard abs(dx) >= 0.5 else {
            return isPetting && time - lastMove > Self.stillness ? reset() : []
        }
        lastMove = time
        let dir: CGFloat = dx > 0 ? 1 : -1
        if direction != 0, dir != direction {
            if abs(previous - strokeStart) >= Self.minStroke { reversals.append(time) }
            strokeStart = previous
        } else if direction == 0 {
            strokeStart = previous
        }
        direction = dir
        reversals.removeAll { time - $0 > Self.window }

        if !isPetting {
            guard reversals.count >= Self.reversalsNeeded else { return [] }
            isPetting = true
            nextHeart = time + Self.heartEvery
            return [.started]
        }
        guard time >= nextHeart else { return [] }
        nextHeart += Self.heartEvery
        return [.heart]
    }

    private mutating func reset() -> [Event] {
        let was = isPetting
        self = PetDetector()
        return was ? [.ended] : []
    }
}

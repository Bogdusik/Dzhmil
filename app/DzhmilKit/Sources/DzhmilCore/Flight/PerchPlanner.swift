import CoreGraphics
import Foundation

public struct ScreenGeometry: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public enum PerchSpot: Equatable, Sendable {
    case air(CGPoint)
    case dock(CGPoint)
    case windowTop(CGPoint)

    public var point: CGPoint {
        switch self {
        case .air(let p), .dock(let p), .windowTop(let p): return p
        }
    }
}

public enum PerchPlanner {
    static let margin: CGFloat = 24
    static let cursorClearance: CGFloat = 200
    static let dodgeTrigger: CGFloat = 90
    static let dodgeClearance: CGFloat = 160

    public static func nextSpot(screen: ScreenGeometry, droneSize: CGSize, cursor: CGPoint, windowTops: [CGRect], using rng: inout some RandomNumberGenerator) -> PerchSpot {
        let roll = Double.random(in: 0..<1, using: &rng)
        if roll >= 0.9 {
            return .dock(dockSpot(screen: screen, droneSize: droneSize))
        }
        if roll >= 0.7, let window = windowTops.randomElement(using: &rng) {
            let p = CGPoint(x: window.midX, y: window.maxY + droneSize.height / 2)
            if clamp(p, droneSize: droneSize, screen: screen) == p {
                return .windowTop(p)
            }
        }
        return .air(airSpot(screen: screen, droneSize: droneSize, cursor: cursor, using: &rng))
    }

    static func airSpot(screen: ScreenGeometry, droneSize: CGSize, cursor: CGPoint, using rng: inout some RandomNumberGenerator) -> CGPoint {
        let area = screen.visibleFrame.insetBy(dx: margin + droneSize.width / 2, dy: margin + droneSize.height / 2)
        guard area.width > 0, area.height > 0 else {
            return CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        }
        var best = CGPoint(x: area.midX, y: area.midY)
        var bestDistance: CGFloat = -1
        for _ in 0..<50 {
            let p = CGPoint(x: CGFloat.random(in: area.minX...area.maxX, using: &rng),
                            y: CGFloat.random(in: area.minY...area.maxY, using: &rng))
            let d = hypot(p.x - cursor.x, p.y - cursor.y)
            if d >= cursorClearance { return p }
            if d > bestDistance { best = p; bestDistance = d }
        }
        let corners = [CGPoint(x: area.minX, y: area.minY), CGPoint(x: area.maxX, y: area.minY),
                        CGPoint(x: area.minX, y: area.maxY), CGPoint(x: area.maxX, y: area.maxY)]
        return corners.max { hypot($0.x - cursor.x, $0.y - cursor.y) < hypot($1.x - cursor.x, $1.y - cursor.y) } ?? best
    }

    public static func dockSpot(screen: ScreenGeometry, droneSize: CGSize) -> CGPoint {
        let f = screen.frame, v = screen.visibleFrame
        if v.minX > f.minX {
            return CGPoint(x: v.minX + droneSize.width / 2, y: v.midY)
        }
        if v.maxX < f.maxX {
            return CGPoint(x: v.maxX - droneSize.width / 2, y: v.midY)
        }
        if v.minY > f.minY {
            return CGPoint(x: v.midX, y: v.minY + droneSize.height / 2)
        }
        return CGPoint(x: f.midX, y: f.minY + droneSize.height / 2 + 4)
    }

    public static func clamp(_ center: CGPoint, droneSize: CGSize, screen: ScreenGeometry) -> CGPoint {
        let v = screen.visibleFrame
        let halfW = droneSize.width / 2, halfH = droneSize.height / 2
        let minY = (v.minY > screen.frame.minY ? v.minY : screen.frame.minY + 4) + halfH
        let x = v.width >= droneSize.width ? min(max(center.x, v.minX + halfW), v.maxX - halfW) : v.midX
        let y = v.maxY - halfH >= minY ? min(max(center.y, minY), v.maxY - halfH) : v.midY
        return CGPoint(x: x, y: y)
    }

    public static func dodge(droneCenter: CGPoint, cursor: CGPoint, screen: ScreenGeometry, droneSize: CGSize) -> CGPoint? {
        let dx = droneCenter.x - cursor.x, dy = droneCenter.y - cursor.y
        guard hypot(dx, dy) < dodgeTrigger else { return nil }
        let away = (dx == 0 && dy == 0) ? 0 : atan2(dy, dx)
        let reach = dodgeClearance + 30
        for i in 0..<16 {
            let offset = Double((i + 1) / 2) * (.pi / 8) * (i % 2 == 0 ? 1 : -1)
            let angle = away + offset
            let candidate = CGPoint(x: cursor.x + cos(angle) * reach, y: cursor.y + sin(angle) * reach)
            let clamped = clamp(candidate, droneSize: droneSize, screen: screen)
            if hypot(clamped.x - cursor.x, clamped.y - cursor.y) >= dodgeClearance {
                return clamped
            }
        }
        return nil
    }
}

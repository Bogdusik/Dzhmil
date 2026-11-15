import CoreGraphics

public struct HitShape: Equatable, Sendable {
    public var droneRect: CGRect
    public var bubbleRect: CGRect?

    public init(droneRect: CGRect, bubbleRect: CGRect?) {
        self.droneRect = droneRect
        self.bubbleRect = bubbleRect
    }

    public func contains(_ p: CGPoint) -> Bool {
        if let bubbleRect, bubbleRect.contains(p) { return true }
        let e = droneRect.insetBy(dx: droneRect.width * 0.1, dy: droneRect.height * 0.1)
        guard e.width > 0, e.height > 0 else { return false }
        let nx = (p.x - e.midX) / (e.width / 2)
        let ny = (p.y - e.midY) / (e.height / 2)
        return nx * nx + ny * ny <= 1
    }
}

public enum Coordinates {
    public static func cgToAppKit(_ r: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryScreenHeight - r.maxY, width: r.width, height: r.height)
    }
}

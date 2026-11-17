import CoreGraphics

public enum PointerLayout {
    static let distance: CGFloat = 170

    public static func droneSpot(target: CGPoint, visibleFrame: CGRect, droneSize: CGSize) -> CGPoint {
        let d = distance / 2.squareRoot()
        let roomLeft = target.x - visibleFrame.minX
        let roomRight = visibleFrame.maxX - target.x
        let x = roomLeft > roomRight ? target.x - d : target.x + d
        let fitsAbove = target.y + d + droneSize.height / 2 <= visibleFrame.maxY
        let y = fitsAbove ? target.y + d : target.y - d
        let halfW = droneSize.width / 2
        let halfH = droneSize.height / 2
        return CGPoint(x: min(max(x, visibleFrame.minX + halfW), visibleFrame.maxX - halfW),
                       y: min(max(y, visibleFrame.minY + halfH), visibleFrame.maxY - halfH))
    }

    public static func arrow(from drone: CGPoint, to target: CGPoint, droneRadius: CGFloat, ringRadius: CGFloat) -> (start: CGPoint, end: CGPoint)? {
        let dx = target.x - drone.x
        let dy = target.y - drone.y
        let length = hypot(dx, dy)
        guard length > droneRadius + ringRadius + 4 else { return nil }
        let ux = dx / length
        let uy = dy / length
        return (CGPoint(x: drone.x + ux * droneRadius, y: drone.y + uy * droneRadius),
                CGPoint(x: target.x - ux * ringRadius, y: target.y - uy * ringRadius))
    }

    static let bow: CGFloat = 0.22

    public static func arcControl(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return start }
        var nx = -dy / length
        var ny = dx / length
        if ny < 0 || (ny == 0 && nx < 0) {
            nx = -nx
            ny = -ny
        }
        return CGPoint(x: (start.x + end.x) / 2 + nx * length * bow, y: (start.y + end.y) / 2 + ny * length * bow)
    }
}

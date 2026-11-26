import QuartzCore
import DzhmilCore

final class HornetLayer: CALayer {
    static let scale: CGFloat = 0.5
    private static let pivot: CGFloat = 14

    private static let hullColor = DronePalette.cg(0x3A3752)
    private static let wingColor = DronePalette.cg(0x2A2840)
    private static let edgeColor = DronePalette.cg(0x1C1B2C)
    private static let accent = DronePalette.cg(0x8B5CFF)
    private static let eyeColor = DronePalette.cg(0xFF3B52)
    private static let rim = DronePalette.cg(0x8B5CFF, alpha: 0.65)

    let wings = CALayer()
    let tail = CALayer()
    let hull = CALayer()
    let cockpit = CALayer()
    let eyes = CALayer()
    let flame = CALayer()

    override init() {
        super.init()
        build()
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        for group in [flame, wings, tail, hull, cockpit] { addSublayer(group) }

        for (width, length, color) in [(34.0, 70.0, DronePalette.cg(0x9B6BFF, alpha: 0.25)), (20, 60, DronePalette.cg(0x9B6BFF, alpha: 0.9)), (9, 36, DronePalette.cg(0xFFF4E0))] {
            let path = CGMutablePath()
            path.move(to: point(-width / 2, 96))
            path.addQuadCurve(to: point(0, 96 + length), control: point(-width / 2, 96 + length * 0.45))
            path.addQuadCurve(to: point(width / 2, 96), control: point(width / 2, 96 + length * 0.45))
            path.closeSubpath()
            flame.addSublayer(fill(path, color))
        }

        mirrored(wings, [(14, 4), (104, 66), (106, 80), (66, 74), (18, 66)], Self.wingColor)
        for side: CGFloat in [-1, 1] { wings.addSublayer(line([(18 * side, 14), (96 * side, 68)], 4, Self.accent)) }
        mirrored(wings, [(96, 52), (108, 52), (110, 90), (98, 90)], Self.edgeColor)

        mirrored(tail, [(13, -46), (46, -22), (44, -14), (15, -22)], Self.wingColor)
        mirrored(tail, [(12, 56), (46, 96), (40, 102), (10, 84)], Self.edgeColor)

        hull.addSublayer(outlined(polygon([(0, -122), (9, -86), (19, -34), (22, 30), (18, 82), (11, 96), (-11, 96), (-18, 82), (-22, 30), (-19, -34), (-9, -86)], Self.hullColor)))
        hull.addSublayer(line([(0, -122), (0, -80)], 3, Self.accent))
        for (i, y) in [16.0, 34, 52].enumerated() {
            hull.addSublayer(polygon([(-18, y), (18, y), (17, y + 7), (-17, y + 7)], DronePalette.cg(0x8B5CFF, alpha: 1 - CGFloat(i) * 0.22)))
        }
        hull.addSublayer(rounded(-12, 88, 24, 12, 4, Self.edgeColor))

        cockpit.addSublayer(rounded(-16, -50, 32, 46, 15, DronePalette.visor))
        cockpit.addSublayer(eyes)
        for side: CGFloat in [-1, 1] {
            let inner = side * 2.55, outer = side * 12.45
            let eye = polygon([(outer, -32.95), (inner, -27.55), (inner, -24.4), (outer, -27.55)], Self.eyeColor)
            eye.shadowColor = Self.eyeColor
            eye.shadowOpacity = 1
            eye.shadowRadius = 4
            eye.shadowOffset = .zero
            eyes.addSublayer(eye)
        }

        let flicker = CABasicAnimation(keyPath: "transform.scale.x")
        flicker.fromValue = 0.82
        flicker.toValue = 1.12
        flicker.duration = 0.07
        flicker.autoreverses = true
        flicker.repeatCount = .infinity
        flame.add(flicker, forKey: "flicker")
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * Self.scale, y: (Self.pivot - y) * Self.scale)
    }

    private func fill(_ path: CGPath, _ color: CGColor) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = color
        return layer
    }

    private func polygon(_ points: [(CGFloat, CGFloat)], _ color: CGColor) -> CAShapeLayer {
        let path = CGMutablePath()
        path.addLines(between: points.map { point($0.0, $0.1) })
        path.closeSubpath()
        let layer = fill(path, color)
        layer.strokeColor = color
        layer.lineWidth = 4 * Self.scale
        layer.lineJoin = .round
        return layer
    }

    private func mirrored(_ parent: CALayer, _ points: [(CGFloat, CGFloat)], _ color: CGColor) {
        for side in [points, points.map { (-$0.0, $0.1) }] {
            parent.addSublayer(outlined(polygon(side, color)))
        }
    }

    private func outlined(_ layer: CAShapeLayer) -> CAShapeLayer {
        layer.strokeColor = Self.rim
        layer.lineWidth = 1.2
        return layer
    }

    private func line(_ points: [(CGFloat, CGFloat)], _ width: CGFloat, _ color: CGColor) -> CAShapeLayer {
        let path = CGMutablePath()
        path.addLines(between: points.map { point($0.0, $0.1) })
        let layer = CAShapeLayer()
        layer.path = path
        layer.strokeColor = color
        layer.fillColor = nil
        layer.lineWidth = width * Self.scale
        layer.lineCap = .round
        return layer
    }

    private func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: CGColor) -> CAShapeLayer {
        let origin = point(x, y + h)
        let rect = CGRect(x: origin.x, y: origin.y, width: w * Self.scale, height: h * Self.scale)
        let radius = r * Self.scale
        return fill(CGPath(roundedRect: rect, cornerWidth: min(radius, rect.width / 2), cornerHeight: min(radius, rect.height / 2), transform: nil), color)
    }
}

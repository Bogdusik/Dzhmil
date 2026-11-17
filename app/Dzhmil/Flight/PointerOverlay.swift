import AppKit
import QuartzCore
import DzhmilCore

@MainActor
final class PointerOverlay {
    static let ringRadius: CGFloat = 20
    static let droneRadius: CGFloat = 46
    static let spotlightRadius: CGFloat = 70
    static let lifetime: Duration = .seconds(30)

    private static let mint = DronePalette.cg(0x7DF3D8)
    private static let teal = DronePalette.body
    private static let deep = DronePalette.cg(0x0A1B20, alpha: 0.92)

    private var panel: NSPanel?
    private let root = CALayer()
    private let dim = CAShapeLayer()
    private let glow = CAGradientLayer()
    private let ring = CAShapeLayer()
    private let reticle = CAShapeLayer()
    private let ripples = [CAShapeLayer(), CAShapeLayer()]
    private let dot = CAShapeLayer()
    private let arrowGlow = CAShapeLayer()
    private let arrowFill = CAGradientLayer()
    private let arrowMask = CAShapeLayer()
    private let head = CAShapeLayer()
    private let comets = [CAShapeLayer(), CAShapeLayer()]
    private let pill = CALayer()
    private let text = CATextLayer()
    private var origin = CGPoint.zero
    private var target = CGPoint.zero
    private var hideTask: Task<Void, Never>?
    private var generation = 0

    var isVisible: Bool { panel?.isVisible == true }

    func show(target: CGPoint, label: String, below window: NSWindow) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(target) }) ?? NSScreen.main else { return }
        generation += 1
        let panel = self.panel ?? makePanel()
        panel.setFrame(screen.frame, display: false)
        origin = screen.frame.origin
        self.target = CGPoint(x: target.x - origin.x, y: target.y - origin.y)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.removeAllAnimations()
        root.opacity = 1
        root.frame = CGRect(origin: .zero, size: screen.frame.size)
        for layer in allLayers { layer.removeAllAnimations() }
        layoutTarget()
        layoutLabel(label)
        for layer in [arrowGlow, arrowFill, head] + comets { layer.isHidden = true }
        CATransaction.commit()

        animateTarget()
        panel.order(.below, relativeTo: window.windowNumber)
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.lifetime)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func showArrow(from droneCenter: CGPoint) {
        guard isVisible else { return }
        let drone = CGPoint(x: droneCenter.x - origin.x, y: droneCenter.y - origin.y)
        guard let straight = PointerLayout.arrow(from: drone, to: target, droneRadius: Self.droneRadius, ringRadius: Self.ringRadius + 10) else { return }
        let control = PointerLayout.arcControl(from: straight.start, to: straight.end)
        let curve = CGMutablePath()
        curve.move(to: straight.start)
        curve.addQuadCurve(to: straight.end, control: control)

        let angle = atan2(straight.end.y - control.y, straight.end.x - control.x)
        let size: CGFloat = 12
        let chevron = CGMutablePath()
        chevron.move(to: CGPoint(x: straight.end.x - size * cos(angle - .pi / 5), y: straight.end.y - size * sin(angle - .pi / 5)))
        chevron.addLine(to: straight.end)
        chevron.addLine(to: CGPoint(x: straight.end.x - size * cos(angle + .pi / 5), y: straight.end.y - size * sin(angle + .pi / 5)))

        let bounds = root.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arrowGlow.path = curve
        arrowMask.path = curve
        arrowFill.frame = bounds
        arrowMask.frame = bounds
        arrowFill.startPoint = CGPoint(x: straight.start.x / bounds.width, y: straight.start.y / bounds.height)
        arrowFill.endPoint = CGPoint(x: straight.end.x / bounds.width, y: straight.end.y / bounds.height)
        head.path = chevron
        for layer in [arrowGlow, arrowFill, head] + comets { layer.isHidden = false }
        head.opacity = 0
        for comet in comets { comet.opacity = 0 }
        CATransaction.commit()

        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.45
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        arrowMask.add(draw, forKey: "draw")
        arrowGlow.add(draw, forKey: "draw")

        let now = CACurrentMediaTime()
        let pop = CABasicAnimation(keyPath: "opacity")
        pop.fromValue = 0
        pop.toValue = 1
        pop.duration = 0.15
        pop.beginTime = now + 0.4
        pop.fillMode = .forwards
        pop.isRemovedOnCompletion = false
        head.add(pop, forKey: "pop")

        for (i, comet) in comets.enumerated() {
            let travel = CAKeyframeAnimation(keyPath: "position")
            travel.path = curve
            travel.calculationMode = .paced
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.15, 0.8, 1]
            let shrink = CAKeyframeAnimation(keyPath: "transform.scale")
            shrink.values = [0.6, 1.1, 0.5]
            let group = CAAnimationGroup()
            group.animations = [travel, fade, shrink]
            group.duration = 1.3
            group.repeatCount = .infinity
            group.beginTime = now + 0.5 + Double(i) * 0.65
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            comet.add(group, forKey: "travel")
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        guard let panel, panel.isVisible else { return }
        let current = generation
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                for layer in self.allLayers { layer.removeAllAnimations() }
                panel.orderOut(nil)
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.2
        root.opacity = 0
        root.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    private var allLayers: [CALayer] {
        [dim, glow, ring, reticle, dot, arrowGlow, arrowFill, arrowMask, head, pill] + ripples + comets
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        ScreenPrivacy.apply(to: p)
        let view = NSView()
        view.layer = root
        view.wantsLayer = true
        p.contentView = view

        dim.fillRule = .evenOdd
        dim.fillColor = CGColor(gray: 0, alpha: 0.28)
        dim.opacity = 0

        glow.type = .radial
        glow.colors = [DronePalette.cg(0x00D4AA, alpha: 0.38), DronePalette.cg(0x00D4AA, alpha: 0)]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)

        ring.fillColor = DronePalette.cg(0x00D4AA, alpha: 0.12)
        ring.strokeColor = Self.teal
        ring.lineWidth = 3
        addGlow(ring, radius: 8)

        reticle.fillColor = nil
        reticle.strokeColor = DronePalette.cg(0x7DF3D8, alpha: 0.85)
        reticle.lineWidth = 1.5
        reticle.lineDashPattern = [5, 7]
        reticle.lineCap = .round

        for ripple in ripples {
            ripple.fillColor = nil
            ripple.strokeColor = Self.mint
            ripple.lineWidth = 2
            ripple.opacity = 0
        }

        dot.fillColor = .white
        addGlow(dot, radius: 6)

        arrowGlow.fillColor = nil
        arrowGlow.strokeColor = DronePalette.cg(0x00D4AA, alpha: 0.28)
        arrowGlow.lineWidth = 11
        arrowGlow.lineCap = .round
        arrowMask.fillColor = nil
        arrowMask.strokeColor = .black
        arrowMask.lineWidth = 3.5
        arrowMask.lineCap = .round
        arrowFill.colors = [Self.mint, Self.teal]
        arrowFill.mask = arrowMask

        head.fillColor = nil
        head.strokeColor = Self.teal
        head.lineWidth = 3.5
        head.lineCap = .round
        head.lineJoin = .round
        addGlow(head, radius: 6)

        for comet in comets {
            let r: CGFloat = 3.5
            comet.bounds = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
            comet.path = CGPath(ellipseIn: comet.bounds, transform: nil)
            comet.fillColor = .white
            comet.opacity = 0
            addGlow(comet, radius: 7)
        }

        pill.backgroundColor = Self.deep
        pill.borderColor = DronePalette.cg(0x00D4AA, alpha: 0.9)
        pill.borderWidth = 1.5
        pill.shadowColor = Self.teal
        pill.shadowOpacity = 0.55
        pill.shadowRadius = 10
        pill.shadowOffset = .zero
        text.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        text.alignmentMode = .center
        text.truncationMode = .end
        pill.addSublayer(text)

        for layer in [dim, glow, arrowGlow, arrowFill, head] + ripples + [reticle, ring, dot] + comets + [pill] {
            root.addSublayer(layer)
        }
        panel = p
        return p
    }

    private func addGlow(_ layer: CALayer, radius: CGFloat) {
        layer.shadowColor = Self.teal
        layer.shadowOpacity = 1
        layer.shadowRadius = radius
        layer.shadowOffset = .zero
    }

    private func circle(_ layer: CAShapeLayer, radius r: CGFloat) {
        let box = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
        layer.bounds = box
        layer.path = CGPath(ellipseIn: box, transform: nil)
        layer.position = target
    }

    private func layoutTarget() {
        let hole = CGMutablePath()
        hole.addRect(root.bounds)
        let s = Self.spotlightRadius
        hole.addEllipse(in: CGRect(x: target.x - s, y: target.y - s, width: s * 2, height: s * 2))
        dim.frame = root.bounds
        dim.path = hole
        dim.opacity = 0

        let g = Self.ringRadius * 3.2
        glow.frame = CGRect(x: target.x - g, y: target.y - g, width: g * 2, height: g * 2)
        circle(ring, radius: Self.ringRadius)
        circle(reticle, radius: Self.ringRadius + 9)
        for ripple in ripples { circle(ripple, radius: Self.ringRadius) }
        circle(dot, radius: 3.5)
    }

    private func layoutLabel(_ label: String) {
        let base = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 13) } ?? base
        let string = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.white])
        let size = string.size()
        let width = min(320, ceil(size.width) + 28)
        let height = ceil(size.height) + 10
        text.string = string
        text.frame = CGRect(x: 14, y: 5, width: width - 28, height: height - 10)
        let gap = Self.ringRadius + 18 + height / 2
        let y = target.y - gap - height / 2 >= 8 ? target.y - gap : target.y + gap
        let x = min(max(target.x, width / 2 + 8), root.bounds.width - width / 2 - 8)
        pill.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        pill.cornerRadius = height / 2
        pill.position = CGPoint(x: x, y: y)
        pill.opacity = 0
    }

    private func animateTarget() {
        let now = CACurrentMediaTime()

        let spot = CAKeyframeAnimation(keyPath: "opacity")
        spot.values = [0, 1, 1, 0]
        spot.keyTimes = [0, 0.12, 0.7, 1]
        spot.duration = 2.6
        dim.add(spot, forKey: "spot")

        let land = CASpringAnimation(keyPath: "transform.scale")
        land.fromValue = 2.4
        land.toValue = 1
        land.damping = 11
        land.stiffness = 180
        land.duration = land.settlingDuration
        let appear = CABasicAnimation(keyPath: "opacity")
        appear.fromValue = 0
        appear.toValue = 1
        appear.duration = 0.25
        for layer in [ring, reticle, glow, dot] {
            layer.add(land, forKey: "land")
            layer.add(appear, forKey: "appear")
        }

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -Double.pi * 2
        spin.duration = 7
        spin.repeatCount = .infinity
        reticle.add(spin, forKey: "spin")

        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 1
        breathe.toValue = 1.5
        breathe.duration = 0.7
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.beginTime = now + 0.5
        dot.add(breathe, forKey: "breathe")

        let glowPulse = CABasicAnimation(keyPath: "opacity")
        glowPulse.fromValue = 1
        glowPulse.toValue = 0.45
        glowPulse.duration = 1.1
        glowPulse.autoreverses = true
        glowPulse.repeatCount = .infinity
        glowPulse.beginTime = now + 0.4
        glow.add(glowPulse, forKey: "pulse")

        for (i, ripple) in ripples.enumerated() {
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 1
            grow.toValue = 2.6
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.85
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [grow, fade]
            group.duration = 1.8
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.repeatCount = .infinity
            group.beginTime = now + 0.35 + Double(i) * 0.9
            ripple.add(group, forKey: "ripple")
        }

        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.6
        pop.toValue = 1
        pop.damping = 12
        pop.stiffness = 220
        pop.duration = pop.settlingDuration
        pop.beginTime = now + 0.2
        pop.fillMode = .backwards
        let show = CABasicAnimation(keyPath: "opacity")
        show.fromValue = 0
        show.toValue = 1
        show.duration = 0.2
        show.beginTime = now + 0.2
        show.fillMode = .forwards
        show.isRemovedOnCompletion = false
        pill.add(pop, forKey: "pop")
        pill.add(show, forKey: "show")
    }
}

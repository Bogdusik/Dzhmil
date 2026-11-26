import AppKit
import QuartzCore
import DzhmilCore

@MainActor
final class HornetStage: NSObject {
    private static let unfold: Double = 1.15
    private static let fold: Double = 0.85
    private static let trailSeconds: Double = 0.55

    var onFinished: (() -> Void)?
    private(set) var isActive = false

    private let sound = HornetSound()
    private var panel: NSPanel?
    private let root = CALayer()
    private let jet = HornetLayer()
    private let drone = CALayer()
    private let flash = CAShapeLayer()
    private let trails = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]
    private var trail: [(time: Double, point: CGPoint)] = []
    private var flight: JetFlight?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var sequence: Task<Void, Never>?
    private var home = CGPoint.zero
    private var origin = CGPoint.zero
    private var ticks = 0

    func start(at center: CGPoint, droneImage: NSImage, soundOn: Bool) {
        guard !isActive, let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return }
        isActive = true
        let panel = self.panel ?? makePanel()
        panel.setFrame(screen.frame, display: false)
        origin = screen.frame.origin
        home = CGPoint(x: center.x - origin.x, y: center.y - origin.y)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = CGRect(origin: .zero, size: screen.frame.size)
        for layer in [drone, jet, flash] + jetParts { layer.removeAllAnimations() }
        jet.flame.add(flicker(), forKey: "flicker")
        jet.position = home
        jet.transform = CATransform3DIdentity
        drone.contents = droneImage
        drone.bounds = CGRect(origin: .zero, size: droneImage.size)
        drone.position = home
        flash.position = home
        trail = []
        for layer in trails { layer.path = nil }
        showJet(false)
        CATransaction.commit()
        panel.orderFrontRegardless()

        sound.enabled = soundOn
        sound.start()
        sound.synth.clank()
        transform(intoJet: true)

        sequence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.unfold))
            guard !Task.isCancelled else { return }
            self?.takeOff(on: screen.frame)
        }
    }

    func returnHome() {
        guard isActive else { return }
        if flight == nil { abort() } else { flight?.comeHome() }
    }

    func abort() {
        guard isActive else { return }
        finish()
    }

    private var jetParts: [CALayer] { [jet.wings, jet.tail, jet.hull, jet.cockpit, jet.eyes, jet.flame] }

    private func takeOff(on frame: CGRect) {
        guard let view = panel?.contentView else { return }
        flight = JetFlight(home: home, screen: CGRect(origin: .zero, size: frame.size))
        ticks = 0
        lastTimestamp = nil
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard var flight else { return }
        let now = link.timestamp
        let dt = min(1.0 / 30, lastTimestamp.map { now - $0 } ?? 1.0 / 60)
        lastTimestamp = now
        var rng = SystemRandomNumberGenerator()
        flight.step(dt: dt, using: &rng)
        self.flight = flight

        if flight.wrapped { trail = [] }
        let bank = 1 - 0.38 * min(1, abs(flight.turn) / JetFlight.turnRate)
        var transform = CATransform3DMakeRotation(CGFloat(flight.heading - .pi / 2), 0, 0, 1)
        transform = CATransform3DScale(transform, CGFloat(bank), 1, 1)
        let nozzle = 43 * HornetLayer.scale * 2
        trail.append((now, CGPoint(x: flight.position.x - CGFloat(cos(flight.heading)) * nozzle, y: flight.position.y - CGFloat(sin(flight.heading)) * nozzle)))
        trail.removeAll { now - $0.time > Self.trailSeconds }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        jet.position = flight.position
        jet.transform = transform
        for (i, layer) in trails.enumerated() {
            let age = Self.trailSeconds * [1.0, 0.6, 0.28][i]
            let points = trail.filter { now - $0.time <= age }.map(\.point)
            let path = CGMutablePath()
            if points.count > 1 { path.addLines(between: points) }
            layer.path = path
        }
        CATransaction.commit()

        sound.synth.setThrottle(Float(flight.speed / JetFlight.cruiseSpeed))
        ticks += 1
        if ticks % 60 == 0, ScreenEnvironment.isFrontmostFullscreen() {
            abort()
            return
        }
        if flight.phase == .home { land() }
    }

    private func land() {
        link?.invalidate()
        link = nil
        flight = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in trails { layer.path = nil }
        CATransaction.commit()
        let turnUpright = CABasicAnimation(keyPath: "transform")
        turnUpright.fromValue = NSValue(caTransform3D: jet.transform)
        turnUpright.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        turnUpright.duration = 0.2
        jet.transform = CATransform3DIdentity
        jet.add(turnUpright, forKey: "upright")
        sound.synth.setThrottle(0)
        sound.synth.clank()
        transform(intoJet: false)
        sequence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fold))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        sequence?.cancel()
        sequence = nil
        link?.invalidate()
        link = nil
        flight = nil
        sound.stop()
        panel?.orderOut(nil)
        isActive = false
        onFinished?()
    }

    private func showJet(_ visible: Bool) {
        drone.opacity = visible ? 0 : 1
        for part in [jet.wings, jet.tail, jet.hull, jet.cockpit, jet.flame] { part.opacity = visible ? 1 : 0 }
    }

    private func transform(intoJet: Bool) {
        let total = intoJet ? Self.unfold : Self.fold
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        showJet(intoJet)
        CATransaction.commit()

        func play(_ layer: CALayer, _ keyPath: String, _ values: [Double], from: Double, to: Double) {
            let a = CAKeyframeAnimation(keyPath: keyPath)
            let ordered = intoJet ? values : values.reversed()
            let start = intoJet ? from : 1 - to
            a.values = ordered
            a.duration = (to - from) * total
            a.beginTime = CACurrentMediaTime() + start * total
            a.fillMode = .both
            a.isRemovedOnCompletion = false
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(a, forKey: keyPath)
        }

        play(drone, "transform.rotation.z", [0, .pi, 2 * .pi], from: 0, to: 0.45)
        play(drone, "transform.scale", [1, 1.15, 0.25], from: 0, to: 0.45)
        play(drone, "opacity", [1, 1, 0], from: 0, to: 0.45)
        play(jet.hull, "transform.scale.y", [0.2, 1.1, 1], from: 0.35, to: 0.68)
        play(jet.hull, "opacity", [0, 1, 1], from: 0.35, to: 0.68)
        play(jet.wings, "transform.scale.x", [0.05, 1.14, 1], from: 0.5, to: 0.85)
        play(jet.wings, "opacity", [0, 1, 1], from: 0.5, to: 0.85)
        play(jet.tail, "transform.scale", [0.1, 1.15, 1], from: 0.62, to: 0.9)
        play(jet.tail, "opacity", [0, 1, 1], from: 0.62, to: 0.9)
        play(jet.cockpit, "opacity", [0, 1, 1], from: 0.45, to: 0.65)
        play(jet.eyes, "opacity", [0, 1, 0.2, 1, 0.4, 1], from: 0.68, to: 0.98)
        play(jet.flame, "opacity", [0, 0, 1], from: 0.75, to: 1)
        play(jet.flame, "transform.scale.y", [0, 1.5, 1], from: 0.75, to: 1)

        let burst = CAAnimationGroup()
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.2
        grow.toValue = 1.7
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        burst.animations = [grow, fade]
        burst.duration = 0.4
        burst.beginTime = CACurrentMediaTime() + total * (intoJet ? 0.33 : 0.4)
        flash.add(burst, forKey: "burst")
    }

    private func flicker() -> CAAnimation {
        let a = CABasicAnimation(keyPath: "transform.scale.x")
        a.fromValue = 0.82
        a.toValue = 1.12
        a.duration = 0.07
        a.autoreverses = true
        a.repeatCount = .infinity
        return a
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

        for (layer, style) in zip(trails, [(14.0, 0.12), (8, 0.24), (3, 0.6)]) {
            layer.fillColor = nil
            layer.strokeColor = DronePalette.cg(0x9B6BFF, alpha: style.1)
            layer.lineWidth = style.0
            layer.lineCap = .round
            layer.lineJoin = .round
            root.addSublayer(layer)
        }
        jet.shadowColor = DronePalette.cg(0x000000)
        jet.shadowOpacity = 0.35
        jet.shadowRadius = 8
        jet.shadowOffset = CGSize(width: 0, height: -6)
        let circle = CGRect(x: -60, y: -60, width: 120, height: 120)
        flash.bounds = circle
        flash.path = CGPath(ellipseIn: circle, transform: nil)
        flash.fillColor = DronePalette.cg(0xD9C8FF)
        flash.opacity = 0
        for layer in [drone, jet, flash] { root.addSublayer(layer) }
        panel = p
        return p
    }
}

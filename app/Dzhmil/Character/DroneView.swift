import AppKit
import QuartzCore
import SwiftUI
import DzhmilCore

enum DronePalette {
    static let body = cg(0x00D4AA)
    static let belly = cg(0x009C82)
    static let shine = cg(0x7DF3D8, alpha: 0.7)
    static let frame = cg(0x20343A)
    static let visor = cg(0x0A1B20)
    static let eye = cg(0x8CFFE4)
    static let uaBlue = cg(0x2B6FE0)
    static let uaYellow = cg(0xFFD23F)

    static func cg(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

struct DroneView: NSViewRepresentable {
    static let width: CGFloat = 124
    static let canvas = CGSize(width: 240, height: 180)
    static var height: CGFloat { width * canvas.height / canvas.width }

    let state: DroneState
    let bankDegrees: Double
    var gesture: GestureRequest? = nil
    var eyeOffset: CGVector = .zero
    var onMake: ((DroneLayerView) -> Void)? = nil

    func makeNSView(context: Context) -> DroneLayerView {
        let v = DroneLayerView(width: Self.width)
        v.apply(state: state)
        v.setBank(bankDegrees)
        onMake?(v)
        return v
    }

    func updateNSView(_ view: DroneLayerView, context: Context) {
        view.apply(state: state)
        view.setBank(bankDegrees)
        view.setEyeOffset(eyeOffset)
        if let gesture { view.play(gesture) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DroneLayerView, context: Context) -> CGSize? {
        CGSize(width: Self.width, height: Self.height)
    }
}

enum DroneGesture: Equatable {
    case idle(IdleGesture)
    case wiggle, startle, cameraFlash
    case steady(fromLeft: Bool)
    case emotion(Emotion)
    case heart
}

struct GestureRequest: Equatable {
    let id: Int
    let gesture: DroneGesture
}

final class DroneLayerView: NSView {
    private let pose = CALayer()
    private let action = CALayer()
    private let bob = CALayer()
    private let canvas = CALayer()

    private var blades: [CALayer] = []
    private var discs: [CAShapeLayer] = []
    private let led = CAShapeLayer()
    private let eyesOpen = CALayer()
    private let eyesBlink = CALayer()
    private let eyesDart = CALayer()
    private let eyesHappy = CALayer()
    private let eyesSad = CALayer()
    private let eyesSleepy = CALayer()
    private let mouth = CALayer()
    private var mouthBars: [CALayer] = []
    private let ring = CAShapeLayer()
    private let zzz = CATextLayer()
    private let yawnMouth = CAShapeLayer()
    private let flash = CAShapeLayer()
    private var eyesBase = CGPoint.zero
    private var lastGestureID: Int?

    private var currentState: DroneState?
    private var petting = false
    private var eyesOverride: DispatchWorkItem?
    private let anchor = CGPoint(x: 0.5, y: 0.55)

    init(width: CGFloat) {
        let height = width * DroneView.canvas.height / DroneView.canvas.width
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
        wantsLayer = true
        layer?.isGeometryFlipped = true
        layer?.masksToBounds = false
        build(size: CGSize(width: width, height: height))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }

    private func build(size: CGSize) {
        guard let root = layer else { return }
        let scale = size.width / DroneView.canvas.width
        let screenScale = NSScreen.main?.backingScaleFactor ?? 2

        for l in [pose, action, bob] {
            l.bounds = CGRect(origin: .zero, size: size)
            l.anchorPoint = anchor
            l.position = CGPoint(x: size.width * anchor.x, y: size.height * anchor.y)
        }
        root.addSublayer(pose)
        pose.addSublayer(action)
        action.addSublayer(bob)

        canvas.bounds = CGRect(origin: .zero, size: DroneView.canvas)
        canvas.anchorPoint = .zero
        canvas.position = .zero
        canvas.transform = CATransform3DMakeScale(scale, scale, 1)
        bob.addSublayer(canvas)

        func stroke(_ points: [(CGFloat, CGFloat)], _ width: CGFloat, _ color: CGColor = DronePalette.frame) -> CAShapeLayer {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: points[0].0, y: points[0].1))
            for pt in points.dropFirst() { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
            let l = CAShapeLayer()
            l.path = p
            l.strokeColor = color
            l.fillColor = nil
            l.lineWidth = width
            l.lineCap = .round
            l.lineJoin = .round
            l.contentsScale = screenScale
            return l
        }

        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: CGColor) -> CAShapeLayer {
            let l = CAShapeLayer()
            l.path = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: min(r, w / 2), cornerHeight: min(r, h / 2), transform: nil)
            l.fillColor = color
            l.contentsScale = screenScale
            return l
        }

        func propeller(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ discH: CGFloat, _ thick: CGFloat) -> CALayer {
            let holder = CALayer()
            holder.bounds = CGRect(x: 0, y: 0, width: r * 2, height: discH)
            holder.position = CGPoint(x: cx, y: cy)
            let disc = CAShapeLayer()
            disc.path = CGPath(ellipseIn: holder.bounds, transform: nil)
            disc.fillColor = DronePalette.frame
            disc.opacity = 0.16
            holder.addSublayer(disc)
            discs.append(disc)
            let squash = CALayer()
            squash.bounds = holder.bounds
            squash.position = CGPoint(x: r, y: discH / 2)
            squash.sublayerTransform = CATransform3DMakeScale(1, 0.3, 1)
            let blade = CAShapeLayer()
            blade.bounds = CGRect(x: 0, y: 0, width: r * 2, height: thick)
            blade.position = CGPoint(x: r, y: discH / 2)
            blade.path = CGPath(roundedRect: blade.bounds, cornerWidth: thick / 2, cornerHeight: thick / 2, transform: nil)
            blade.fillColor = DronePalette.frame
            squash.addSublayer(blade)
            holder.addSublayer(squash)
            blades.append(blade)
            return holder
        }

        let c = canvas
        c.addSublayer(stroke([(96, 82), (54, 56)], 8))
        c.addSublayer(stroke([(144, 82), (186, 56)], 8))
        c.addSublayer(box(47, 46, 14, 13, 3, DronePalette.frame))
        c.addSublayer(box(179, 46, 14, 13, 3, DronePalette.frame))
        c.addSublayer(propeller(54, 44, 30, 18, 8))
        c.addSublayer(propeller(186, 44, 30, 18, 8))

        c.addSublayer(stroke([(150, 66), (166, 40)], 3))
        led.bounds = CGRect(x: 0, y: 0, width: 9, height: 9)
        led.position = CGPoint(x: 166, y: 39)
        led.path = CGPath(ellipseIn: led.bounds, transform: nil)
        led.fillColor = DronePalette.uaYellow
        c.addSublayer(led)

        c.addSublayer(stroke([(102, 136), (96, 150)], 4))
        c.addSublayer(stroke([(138, 136), (144, 150)], 4))

        c.addSublayer(box(78, 66, 84, 62, 26, DronePalette.belly))
        c.addSublayer(box(78, 60, 84, 62, 26, DronePalette.body))
        c.addSublayer(box(96, 65, 30, 5, 2.5, DronePalette.shine))
        c.addSublayer(box(87, 76, 66, 34, 15, DronePalette.visor))
        flash.path = CGPath(roundedRect: CGRect(x: 87, y: 76, width: 66, height: 34), cornerWidth: 15, cornerHeight: 15, transform: nil)
        flash.fillColor = DronePalette.cg(0xFFFFFF)
        flash.opacity = 0
        c.addSublayer(box(94, 123, 52, 17, 5, DronePalette.frame))
        c.addSublayer(box(111, 123, 18, 8.5, 0, DronePalette.uaBlue))
        c.addSublayer(box(111, 131.5, 18, 8.5, 0, DronePalette.uaYellow))

        let eyeBox = CGRect(x: 101, y: 84, width: 38, height: 14)
        for l in [eyesOpen, eyesBlink, eyesDart] {
            l.bounds = CGRect(origin: .zero, size: eyeBox.size)
            l.position = CGPoint(x: eyeBox.width / 2, y: eyeBox.height / 2)
        }
        eyesOpen.position = CGPoint(x: eyeBox.midX, y: eyeBox.midY)
        eyesBase = eyesOpen.position
        eyesOpen.addSublayer(eyesBlink)
        eyesBlink.addSublayer(eyesDart)
        eyesDart.addSublayer(box(0, 0, 10, 14, 5, DronePalette.eye))
        eyesDart.addSublayer(box(28, 0, 10, 14, 5, DronePalette.eye))
        c.addSublayer(eyesOpen)

        eyesHappy.addSublayer(stroke([(100, 95), (106, 87), (112, 95)], 3.2, DronePalette.eye))
        eyesHappy.addSublayer(stroke([(128, 95), (134, 87), (140, 95)], 3.2, DronePalette.eye))
        c.addSublayer(eyesHappy)

        eyesSad.addSublayer(stroke([(100, 90), (112, 85)], 3, DronePalette.eye))
        eyesSad.addSublayer(stroke([(128, 85), (140, 90)], 3, DronePalette.eye))
        eyesSad.addSublayer(box(101, 94, 10, 8, 4, DronePalette.eye))
        eyesSad.addSublayer(box(129, 94, 10, 8, 4, DronePalette.eye))
        c.addSublayer(eyesSad)

        for x: CGFloat in [100, 128] {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x, y: 90))
            p.addQuadCurve(to: CGPoint(x: x + 12, y: 90), control: CGPoint(x: x + 6, y: 96))
            let l = CAShapeLayer()
            l.path = p
            l.strokeColor = DronePalette.eye
            l.fillColor = nil
            l.lineWidth = 3.2
            l.lineCap = .round
            eyesSleepy.addSublayer(l)
        }
        c.addSublayer(eyesSleepy)

        for i in 0..<3 {
            let bar = box(0, 0, 3.5, 4, 1.5, DronePalette.eye)
            bar.bounds = CGRect(x: 0, y: 0, width: 3.5, height: 4)
            bar.path = CGPath(roundedRect: bar.bounds, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            bar.position = CGPoint(x: 114.75 + CGFloat(i) * 5.2, y: 103)
            mouth.addSublayer(bar)
            mouthBars.append(bar)
        }
        c.addSublayer(mouth)
        yawnMouth.bounds = CGRect(x: 0, y: 0, width: 10, height: 8)
        yawnMouth.position = CGPoint(x: 120, y: 103)
        yawnMouth.path = CGPath(ellipseIn: yawnMouth.bounds, transform: nil)
        yawnMouth.fillColor = DronePalette.eye
        yawnMouth.opacity = 0
        c.addSublayer(yawnMouth)
        c.addSublayer(flash)

        c.addSublayer(stroke([(92, 108), (40, 122)], 10))
        c.addSublayer(stroke([(148, 108), (200, 122)], 10))
        c.addSublayer(box(31, 107, 18, 17, 4, DronePalette.frame))
        c.addSublayer(box(191, 107, 18, 17, 4, DronePalette.frame))
        c.addSublayer(propeller(40, 104, 38, 22, 10))
        c.addSublayer(propeller(200, 104, 38, 22, 10))

        ring.bounds = CGRect(x: 0, y: 0, width: 168, height: 168)
        ring.position = CGPoint(x: 120, y: 93.6)
        ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
        ring.strokeColor = DronePalette.body
        ring.fillColor = nil
        ring.lineWidth = 2
        c.addSublayer(ring)

        zzz.string = "z z z"
        zzz.font = NSFont.monospacedSystemFont(ofSize: 22, weight: .semibold)
        zzz.fontSize = 22
        zzz.foregroundColor = DronePalette.cg(0x20343A, alpha: 0.75)
        zzz.contentsScale = screenScale
        zzz.bounds = CGRect(x: 0, y: 0, width: 90, height: 28)
        zzz.position = CGPoint(x: 190, y: 20)
        c.addSublayer(zzz)
    }

    func setBank(_ degrees: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pose.transform = CATransform3DMakeRotation(CGFloat(degrees * .pi / 180), 0, 0, 1)
        CATransaction.commit()
    }

    func apply(state: DroneState) {
        guard state != currentState else { return }
        let previous = currentState
        currentState = state
        eyesOverride?.cancel()
        eyesOverride = nil
        let face = DroneFace.face(for: state)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        eyesOpen.isHidden = ![.open, .wide, .darting].contains(face.eyes)
        eyesHappy.isHidden = face.eyes != .happy
        eyesSad.isHidden = face.eyes != .sad
        eyesSleepy.isHidden = face.eyes != .sleepy
        eyesOpen.transform = face.eyes == .wide ? CATransform3DMakeScale(1.25, 1.25, 1) : CATransform3DIdentity
        mouth.isHidden = !face.mouthTalking
        ring.isHidden = !face.ring
        zzz.isHidden = !face.zzz

        setLoop(eyesBlink, "blink", eyesOpen.isHidden ? nil : {
            let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
            a.values = [1, 1, 0.1, 1]
            a.keyTimes = [0, 0.93, 0.96, 1]
            a.duration = 4.2
            return a
        }())
        setLoop(eyesDart, "dart", face.eyes == .darting ? pingPong("transform.translation.x", -3, 3, 0.35) : nil)

        for blade in blades {
            setLoop(blade, "spin", face.propellersSpinning ? {
                let a = CABasicAnimation(keyPath: "transform.rotation.z")
                a.fromValue = 0
                a.toValue = Double.pi * 2
                a.duration = 0.24
                a.timingFunction = CAMediaTimingFunction(name: .linear)
                return a
            }() : nil)
        }
        for disc in discs { disc.opacity = face.propellersSpinning ? 0.16 : 0 }
        setLoop(bob, "bob", face.propellersSpinning ? pingPong("transform.translation.y", -5, 5, 1.3, ease: true) : nil)

        switch face.led {
        case .dim:
            setLoop(led, "led", nil)
            led.opacity = 0.35
        case .slow, .fast:
            led.opacity = 1
            setLoop(led, "led", pingPong("opacity", 1, 0.25, face.led == .fast ? 0.25 : 0.8, ease: true))
        }

        for (i, bar) in mouthBars.enumerated() {
            let a = face.mouthTalking ? pingPong("transform.scale.y", 0.4, 1.5, 0.25, ease: true) : nil
            a?.beginTime = CACurrentMediaTime() + Double(i) * 0.12
            setLoop(bar, "talk", a)
        }

        setLoop(ring, "ring", face.ring ? {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.7
            scale.toValue = 1.5
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [scale, fade]
            g.duration = 1.4
            g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            return g
        }() : nil)

        setLoop(zzz, "zzz", face.zzz ? {
            let move = CABasicAnimation(keyPath: "transform.translation")
            move.fromValue = NSValue(size: CGSize(width: -10, height: 0))
            move.toValue = NSValue(size: CGSize(width: 10, height: -30))
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [move, fade]
            g.duration = 2.4
            return g
        }() : nil)

        CATransaction.commit()

        if state == .celebrating, previous != .celebrating { playFlip() }
        if state == .error, previous != .error { playShake() }
    }

    private func pingPong(_ keyPath: String, _ from: Double, _ to: Double, _ duration: Double, ease: Bool = true) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: keyPath)
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        a.autoreverses = true
        a.timingFunction = CAMediaTimingFunction(name: ease ? .easeInEaseOut : .linear)
        return a
    }

    private func setLoop(_ layer: CALayer, _ key: String, _ animation: CAAnimation?) {
        guard let animation else {
            layer.removeAnimation(forKey: key)
            return
        }
        guard layer.animation(forKey: key) == nil else { return }
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: key)
    }

    private func playFlip() {
        let spin = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        spin.values = [0, 200 * Double.pi / 180, 2 * Double.pi]
        spin.keyTimes = [0, 0.45, 1]
        let lift = CAKeyframeAnimation(keyPath: "transform.translation.y")
        lift.values = [0, -26, 0]
        lift.keyTimes = [0, 0.45, 1]
        let g = CAAnimationGroup()
        g.animations = [spin, lift]
        g.duration = 0.95
        g.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        action.add(g, forKey: "flip")
    }

    func setEyeOffset(_ offset: CGVector) {
        let target = CGPoint(x: eyesBase.x + offset.dx, y: eyesBase.y - offset.dy)
        guard abs(eyesOpen.position.x - target.x) > 0.05 || abs(eyesOpen.position.y - target.y) > 0.05 else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        eyesOpen.position = target
        CATransaction.commit()
    }

    func play(_ request: GestureRequest) {
        guard request.id != lastGestureID else { return }
        lastGestureID = request.id
        switch request.gesture {
        case .idle(.lookAround):
            eyesDart.add(keyframes("transform.translation.x", [0, -4, -4, 4, 4, 0], [0, 0.15, 0.4, 0.55, 0.8, 1], 1.2), forKey: "look")
        case .idle(.tilt):
            let angle = (Bool.random() ? 8.0 : -8.0) * Double.pi / 180
            action.add(keyframes("transform.rotation.z", [0, angle, angle, 0], [0, 0.2, 0.75, 1], 1.6), forKey: "tilt")
        case .idle(.hop):
            action.add(keyframes("transform.translation.y", [0, -12, 0, -4, 0], [0, 0.3, 0.6, 0.8, 1], 0.7), forKey: "hop")
        case .idle(.yawn):
            yawnMouth.add(keyframes("opacity", [0, 1, 1, 0], [0, 0.2, 0.8, 1], 1.4), forKey: "yawn")
            yawnMouth.add(keyframes("transform.scale", [0.4, 1.2, 1.1, 0.4], [0, 0.3, 0.8, 1], 1.4), forKey: "yawnScale")
            eyesDart.add(keyframes("transform.scale.y", [1, 0.35, 0.35, 1], [0, 0.2, 0.8, 1], 1.4), forKey: "squint")
        case .idle(.barrelRoll):
            let roll = keyframes("transform.scale.x", [1, 0, -1, 0, 1], [0, 0.25, 0.5, 0.75, 1], 0.8)
            let lift = keyframes("transform.translation.y", [0, -10, 0], [0, 0.5, 1], 0.8)
            action.add(group([roll, lift], 0.8), forKey: "roll")
        case .wiggle:
            action.add(keyframes("transform.rotation.z", [0, 6, -6, 6, -6, 0].map { $0 * Double.pi / 180 }, nil, 0.9), forKey: "wiggle")
            showEyes(eyesHappy, for: 1.0)
        case .startle:
            eyesDart.add(keyframes("transform.scale", [1, 1.4, 1.4, 1], [0, 0.15, 0.7, 1], 0.5), forKey: "startle")
            action.add(keyframes("transform.translation.y", [0, -8, 0], [0, 0.3, 1], 0.4), forKey: "jump")
        case .steady(let fromLeft):
            let sign = fromLeft ? -1.0 : 1.0
            let tilt = keyframes("transform.rotation.z", [0, 8, -5, 3, -1.5, 0].map { $0 * sign * Double.pi / 180 }, nil, 1.0)
            let bob = keyframes("transform.translation.y", [0, 5, -3, 1.5, 0], nil, 1.0)
            action.add(group([tilt, bob], 1.0), forKey: "steady")
        case .emotion(let emotion):
            play(emotion)
        case .heart:
            floatHeart()
        case .cameraFlash:
            flash.add(keyframes("opacity", [0, 0.9, 0, 0.9, 0], [0, 0.15, 0.45, 0.6, 1], 0.7), forKey: "flash")
            led.add(keyframes("transform.scale", [1, 1.8, 1], [0, 0.5, 1], 0.7), forKey: "pulse")
        }
    }

    private func keyframes(_ keyPath: String, _ values: [Double], _ times: [NSNumber]?, _ duration: Double) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = values
        a.keyTimes = times
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return a
    }

    private func group(_ animations: [CAAnimation], _ duration: Double) -> CAAnimationGroup {
        let g = CAAnimationGroup()
        g.animations = animations
        g.duration = duration
        return g
    }

    private func play(_ emotion: Emotion) {
        switch emotion {
        case .happy:
            showEyes(eyesHappy, for: 1.5)
            action.add(keyframes("transform.translation.y", [0, -10, 0, -3, 0], [0, 0.3, 0.6, 0.8, 1], 0.7), forKey: "hop")
        case .laugh:
            showEyes(eyesHappy, for: 1.2)
            action.add(keyframes("transform.rotation.z", [0, 5, -5, 5, -5, 0].map { $0 * Double.pi / 180 }, nil, 0.8), forKey: "wiggle")
            action.add(keyframes("transform.translation.y", [0, -4, 0, -4, 0], nil, 0.8), forKey: "giggle")
        case .surprised:
            eyesDart.add(keyframes("transform.scale", [1, 1.35, 1.35, 1], [0, 0.12, 0.75, 1], 0.9), forKey: "surprise")
            action.add(keyframes("transform.translation.y", [0, -7, 0], [0, 0.3, 1], 0.45), forKey: "jump")
        case .thinking:
            let angle = -7 * Double.pi / 180
            action.add(keyframes("transform.rotation.z", [0, angle, angle, 0], [0, 0.2, 0.8, 1], 1.8), forKey: "tilt")
            eyesDart.add(keyframes("transform.translation.y", [0, -3, -3, 0], [0, 0.2, 0.8, 1], 1.8), forKey: "ponderY")
            eyesDart.add(keyframes("transform.translation.x", [0, 3, 3, 0], [0, 0.2, 0.8, 1], 1.8), forKey: "ponderX")
        case .sad:
            showEyes(eyesSad, for: 2.0)
            action.add(keyframes("transform.translation.y", [0, 6, 6, 0], [0, 0.25, 0.8, 1], 2.0), forKey: "droop")
        }
    }

    func setPetting(_ on: Bool) {
        guard on != petting else { return }
        petting = on
        if on {
            showEyes(eyesHappy, for: nil)
            let rock = pingPong("transform.rotation.z", -4 * Double.pi / 180, 4 * Double.pi / 180, 0.7)
            action.add(rock, forKey: "pet")
        } else {
            action.removeAnimation(forKey: "pet")
            restoreEyes()
        }
    }

    private func floatHeart() {
        let heart = CAShapeLayer()
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 11, y: 20))
        p.addCurve(to: CGPoint(x: 0, y: 7), control1: CGPoint(x: 5, y: 15), control2: CGPoint(x: 0, y: 11))
        p.addCurve(to: CGPoint(x: 11, y: 4), control1: CGPoint(x: 0, y: 1), control2: CGPoint(x: 8, y: -1))
        p.addCurve(to: CGPoint(x: 22, y: 7), control1: CGPoint(x: 14, y: -1), control2: CGPoint(x: 22, y: 1))
        p.addCurve(to: CGPoint(x: 11, y: 20), control1: CGPoint(x: 22, y: 11), control2: CGPoint(x: 17, y: 15))
        heart.path = p
        heart.fillColor = DronePalette.cg(0xFF6B8B)
        heart.bounds = CGRect(x: 0, y: 0, width: 22, height: 20)
        heart.position = CGPoint(x: .random(in: 130...170), y: 30)
        heart.opacity = 0
        canvas.addSublayer(heart)
        let rise = keyframes("position.y", [30, -20], nil, 1.6)
        let drift = keyframes("position.x", [heart.position.x, heart.position.x + 8, heart.position.x - 4], nil, 1.6)
        let fade = keyframes("opacity", [0, 1, 1, 0], [0, 0.15, 0.6, 1], 1.6)
        let grow = keyframes("transform.scale", [0.5, 1.1, 1], [0, 0.3, 1], 1.6)
        CATransaction.begin()
        CATransaction.setCompletionBlock { heart.removeFromSuperlayer() }
        heart.add(group([rise, drift, fade, grow], 1.6), forKey: "float")
        CATransaction.commit()
    }

    private func showEyes(_ eyes: CALayer, for seconds: Double?) {
        guard currentState != nil, !(petting && seconds != nil) else { return }
        guard !eyesOpen.isHidden || eyesOverride != nil || petting else { return }
        eyesOverride?.cancel()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [eyesOpen, eyesHappy, eyesSad] { layer.isHidden = layer !== eyes }
        CATransaction.commit()
        guard let seconds else { return }
        let restore = DispatchWorkItem { [weak self] in
            guard let self, !petting else { return }
            restoreEyes()
        }
        eyesOverride = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: restore)
    }

    private func restoreEyes() {
        eyesOverride?.cancel()
        eyesOverride = nil
        guard let state = currentState else { return }
        let face = DroneFace.face(for: state)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        eyesOpen.isHidden = ![.open, .wide, .darting].contains(face.eyes)
        eyesHappy.isHidden = face.eyes != .happy
        eyesSad.isHidden = face.eyes != .sad
        CATransaction.commit()
    }

    private func playShake() {
        let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        shake.values = [0, -9, 9, -6, 0].map { $0 * Double.pi / 180 }
        shake.duration = 0.54
        action.add(shake, forKey: "shake")
    }

    func renderImage(scale: CGFloat = 2) -> NSImage? {
        guard let root = layer else { return nil }
        let size = bounds.size
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        root.render(in: ctx)
        return ctx.makeImage().map { NSImage(cgImage: $0, size: size) }
    }
}

import AppKit
import QuartzCore
import DzhmilCore

@MainActor
final class PointerOverlay {
    static let ringRadius: CGFloat = 22
    static let droneRadius: CGFloat = 46
    static let lifetime: Duration = .seconds(30)

    private var panel: NSPanel?
    private let root = CALayer()
    private let ring = CAShapeLayer()
    private let pulse = CAShapeLayer()
    private let line = CAShapeLayer()
    private let head = CAShapeLayer()
    private let pill = CALayer()
    private let text = CATextLayer()
    private var origin = CGPoint.zero
    private var target = CGPoint.zero
    private var hideTask: Task<Void, Never>?

    var isVisible: Bool { panel?.isVisible == true }

    func show(target: CGPoint, label: String, below window: NSWindow) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(target) }) ?? NSScreen.main else { return }
        let panel = self.panel ?? makePanel()
        panel.setFrame(screen.frame, display: false)
        origin = screen.frame.origin
        self.target = CGPoint(x: target.x - origin.x, y: target.y - origin.y)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = CGRect(origin: .zero, size: screen.frame.size)
        layoutRing()
        layoutLabel(label)
        line.isHidden = true
        head.isHidden = true
        CATransaction.commit()

        startPulse()
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
        guard let arrow = PointerLayout.arrow(from: drone, to: target, droneRadius: Self.droneRadius, ringRadius: Self.ringRadius + 4) else { return }
        let path = CGMutablePath()
        path.move(to: arrow.start)
        path.addLine(to: arrow.end)
        let angle = atan2(arrow.end.y - arrow.start.y, arrow.end.x - arrow.start.x)
        let tip = CGMutablePath()
        let size: CGFloat = 11
        tip.move(to: arrow.end)
        tip.addLine(to: CGPoint(x: arrow.end.x - size * cos(angle - .pi / 7), y: arrow.end.y - size * sin(angle - .pi / 7)))
        tip.addLine(to: CGPoint(x: arrow.end.x - size * cos(angle + .pi / 7), y: arrow.end.y - size * sin(angle + .pi / 7)))
        tip.closeSubpath()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        line.path = path
        head.path = tip
        line.isHidden = false
        head.isHidden = false
        CATransaction.commit()

        let march = CABasicAnimation(keyPath: "lineDashPhase")
        march.fromValue = 0
        march.toValue = -14
        march.duration = 0.5
        march.repeatCount = .infinity
        line.add(march, forKey: "march")
        let grow = CABasicAnimation(keyPath: "strokeEnd")
        grow.fromValue = 0
        grow.toValue = 1
        grow.duration = 0.25
        line.add(grow, forKey: "grow")
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        guard let panel, panel.isVisible else { return }
        pulse.removeAllAnimations()
        line.removeAllAnimations()
        panel.orderOut(nil)
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
        let view = NSView()
        view.layer = root
        view.wantsLayer = true
        p.contentView = view

        let teal = DronePalette.body
        ring.fillColor = DronePalette.cg(0x00D4AA, alpha: 0.12)
        ring.strokeColor = teal
        ring.lineWidth = 3
        pulse.fillColor = nil
        pulse.strokeColor = teal
        pulse.lineWidth = 2
        line.strokeColor = teal
        line.fillColor = nil
        line.lineWidth = 3
        line.lineCap = .round
        line.lineDashPattern = [8, 6]
        head.fillColor = teal
        pill.backgroundColor = DronePalette.cg(0x0A1B20, alpha: 0.9)
        pill.borderColor = teal
        pill.borderWidth = 1.5
        pill.cornerRadius = 11
        text.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        text.alignmentMode = .center
        for layer in [line, head, pulse, ring, pill] { root.addSublayer(layer) }
        pill.addSublayer(text)
        panel = p
        return p
    }

    private func layoutRing() {
        let r = Self.ringRadius
        let box = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
        for layer in [ring, pulse] {
            layer.bounds = box
            layer.path = CGPath(ellipseIn: box, transform: nil)
            layer.position = target
        }
    }

    private func layoutLabel(_ label: String) {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let string = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.white])
        let size = string.size()
        let width = min(320, ceil(size.width) + 20)
        let height = ceil(size.height) + 6
        text.string = string
        text.truncationMode = .end
        text.frame = CGRect(x: 10, y: 3, width: width - 20, height: height - 6)
        let gap = Self.ringRadius + 10 + height / 2
        let y = target.y - gap - height / 2 >= 0 ? target.y - gap : target.y + gap
        let x = min(max(target.x, width / 2 + 4), root.bounds.width - width / 2 - 4)
        pill.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        pill.position = CGPoint(x: x, y: y)
    }

    private func startPulse() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 1.9
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.2
        group.repeatCount = .infinity
        pulse.add(group, forKey: "pulse")
    }
}

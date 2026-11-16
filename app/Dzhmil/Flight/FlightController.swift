import AppKit
import QuartzCore
import DzhmilCore

@MainActor
final class FlightController: NSObject {
    private let panel: DronePanel
    private var model: FlightModel
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var arrival: (() -> Void)?

    var onUpdate: ((_ bank: Double, _ speed: Double) -> Void)?

    init(panel: DronePanel) {
        self.panel = panel
        self.model = FlightModel(position: panel.droneCenter)
        super.init()
    }

    var droneCenter: CGPoint { model.position }
    var target: CGPoint { model.target }
    var isMoving: Bool { link?.isPaused == false }

    func place(at center: CGPoint) {
        stop()
        model = FlightModel(position: center)
        panel.setFrameOrigin(panel.origin(forDroneCenter: center))
        onUpdate?(0, 0)
    }

    func fly(to center: CGPoint, completion: (() -> Void)? = nil) {
        arrival = completion
        model.target = center
        if link == nil, let view = panel.contentView {
            let l = view.displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        lastTimestamp = nil
        link?.isPaused = false
    }

    func stop() {
        link?.isPaused = true
        lastTimestamp = nil
        arrival = nil
        model.velocity = .zero
        model.target = model.position
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = min(1.0 / 30, lastTimestamp.map { now - $0 } ?? 1.0 / 60)
        lastTimestamp = now
        model.step(dt: dt)
        panel.setFrameOrigin(panel.origin(forDroneCenter: model.position))
        onUpdate?(model.bankDegrees, hypot(model.velocity.dx, model.velocity.dy))
        if model.isSettled {
            link.isPaused = true
            lastTimestamp = nil
            onUpdate?(0, 0)
            let done = arrival
            arrival = nil
            done?()
        }
    }
}

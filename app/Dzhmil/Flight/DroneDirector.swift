import AppKit
import SwiftUI
import DzhmilCore

@MainActor
final class DroneDirector {
    static let wanderInterval: ClosedRange<TimeInterval> = 180...480
    static let dragLock: TimeInterval = 600
    static let dayIdle: TimeInterval = 600
    static let nightIdle: TimeInterval = 180
    static let dodgeCursorSpeed: CGFloat = 800

    let panel = DronePanel()
    let model = CompanionViewModel()
    let hum = PropellerHum()
    private(set) lazy var flight = FlightController(panel: panel)
    private(set) var machine = BehaviorMachine()

    private var lifeTimer: Timer?
    private var hitTimer: Timer?
    private var nextWanderAt = Date().addingTimeInterval(120)
    private var dragLockUntil = Date.distantPast
    private var dodgeCooldownUntil = Date.distantPast
    private var dragStart: (mouse: CGPoint, center: CGPoint)?
    private var lastMouse: (point: CGPoint, time: TimeInterval)?
    private var isFullscreen = false
    private var ticks = 0
    private(set) var isHidden = false

    var idleOverride: TimeInterval?

    func start() {
        let host = ClickThroughHostingView(rootView: CompanionView(model: model))
        host.frame = CGRect(origin: .zero, size: DronePanel.size)
        host.sizingOptions = []
        panel.contentView = host

        flight.onUpdate = { [weak self] bank, speed in
            guard let self else { return }
            model.bankDegrees = bank
            hum.setIntensity(speed / FlightModel.maxSpeed)
        }
        model.onDrag = { [weak self] phase in self?.handleDrag(phase) }
        flight.onInterrupted = { [weak self] in
            guard let self, machine.state == .flying else { return }
            send(.arrived)
        }

        let dock = PerchPlanner.dockSpot(screen: ScreenEnvironment.currentScreen(), droneSize: DronePanel.droneSize)
        flight.place(at: dock)
        panel.orderFrontRegardless()
        takeOff()

        lifeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lifeTick() }
        }
        hitTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hitTick() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reclamp() }
        }
    }

    @discardableResult
    func send(_ event: BehaviorEvent) -> [BehaviorEffect] {
        let effects = machine.handle(event)
        model.state = machine.state
        var rest: [BehaviorEffect] = []
        for effect in effects {
            switch effect {
            case .flyToDock: flight.fly(to: dockSpot())
            case .wakeUp: takeOff()
            default: rest.append(effect)
            }
        }
        return rest
    }

    func setHidden(_ hidden: Bool) {
        isHidden = hidden
        hidden ? panel.orderOut(nil) : panel.orderFrontRegardless()
    }

    func setQuiet(_ quiet: Bool) {
        send(.quietChanged(quiet))
    }

    func ensureBubbleFits() {
        let center = flight.isMoving ? flight.target : flight.droneCenter
        let safe = PerchPlanner.bubbleSafeCenter(center, panelSize: DronePanel.size, droneOffset: DronePanel.droneCenterOffset, screen: screenGeometry())
        guard safe != center else { return }
        flight.fly(to: safe)
    }

    private func dockSpot() -> CGPoint {
        PerchPlanner.dockSpot(screen: ScreenEnvironment.currentScreen(), droneSize: DronePanel.droneSize)
    }

    private func screenGeometry() -> ScreenGeometry {
        ScreenEnvironment.geometry(for: ScreenEnvironment.screen(containing: flight.droneCenter))
    }

    private func takeOff() {
        let screen = screenGeometry()
        let up = PerchPlanner.clamp(CGPoint(x: flight.droneCenter.x, y: flight.droneCenter.y + 160), droneSize: DronePanel.droneSize, screen: screen)
        cruise(to: up)
    }

    private func cruise(to point: CGPoint, then: (() -> Void)? = nil) {
        flight.interrupt()
        if machine.canWander {
            send(.wanderStarted)
            flight.fly(to: point) { [weak self] in
                self?.send(.arrived)
                then?()
            }
        } else {
            flight.fly(to: point) { then?() }
        }
    }

    private func lifeTick() {
        ticks += 1
        let sinceInput = ScreenEnvironment.secondsSinceUserInput()
        let hour = Calendar.current.component(.hour, from: Date())
        let threshold = idleOverride ?? ((hour >= 23 || hour < 7) ? Self.nightIdle : Self.dayIdle)

        if machine.state == .sleeping {
            if sinceInput < 2 { send(.userActive) }
        } else if machine.state == .hover, sinceInput >= threshold, model.bubble == nil, dragStart == nil {
            cruise(to: dockSpot()) { [weak self] in self?.send(.userIdle) }
            return
        }

        if ticks % 2 == 0 {
            let fs = ScreenEnvironment.isFrontmostFullscreen()
            if fs != isFullscreen {
                isFullscreen = fs
                send(.fullscreenChanged(fs))
                panel.animator().alphaValue = fs ? 0.25 : 1
                if fs {
                    let s = screenGeometry()
                    flight.fly(to: PerchPlanner.clamp(CGPoint(x: s.visibleFrame.maxX, y: s.visibleFrame.minY), droneSize: DronePanel.droneSize, screen: s))
                }
            }
        }

        let now = Date()
        if machine.canWander, !isHidden, now >= nextWanderAt, now >= dragLockUntil, model.bubble == nil, dragStart == nil, !flight.isMoving {
            nextWanderAt = now.addingTimeInterval(.random(in: Self.wanderInterval))
            let screen = ScreenEnvironment.currentScreen()
            var rng = SystemRandomNumberGenerator()
            let spot = PerchPlanner.nextSpot(screen: screen, droneSize: DronePanel.droneSize, cursor: ScreenEnvironment.cursor(),
                                             windowTops: ScreenEnvironment.windowTops(on: screen), using: &rng)
            cruise(to: spot.point)
        }
    }

    private func hitTick() {
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let now = ProcessInfo.processInfo.systemUptime
        let speed = lastMouse.map { hypot(mouse.x - $0.point.x, mouse.y - $0.point.y) / max(0.001, now - $0.time) } ?? 0
        lastMouse = (mouse, now)

        let local = CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
        let shape = HitShape(droneRect: DronePanel.droneRect, bubbleRect: model.bubbleRect)
        let overDrone = frame.contains(mouse) && shape.contains(local)
        if dragStart == nil {
            let ignore = !overDrone
            if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
        }

        guard !overDrone, speed > Self.dodgeCursorSpeed, machine.canWander, model.bubble == nil, dragStart == nil,
              !flight.isMoving, Date() >= dodgeCooldownUntil, Date() >= dragLockUntil else { return }
        if let target = PerchPlanner.dodge(droneCenter: flight.droneCenter, cursor: mouse, screen: screenGeometry(), droneSize: DronePanel.droneSize) {
            dodgeCooldownUntil = Date().addingTimeInterval(5)
            cruise(to: target)
        }
    }

    private func handleDrag(_ phase: DragPhase) {
        let mouse = NSEvent.mouseLocation
        switch phase {
        case .changed:
            if dragStart == nil {
                if machine.state == .flying { send(.arrived) }
                flight.stop()
                dragStart = (mouse, flight.droneCenter)
            }
            guard let start = dragStart else { return }
            flight.place(at: CGPoint(x: start.center.x + mouse.x - start.mouse.x, y: start.center.y + mouse.y - start.mouse.y))
        case .ended:
            dragStart = nil
            dragLockUntil = Date().addingTimeInterval(Self.dragLock)
            let clamped = PerchPlanner.clamp(flight.droneCenter, droneSize: DronePanel.droneSize, screen: screenGeometry())
            if clamped != flight.droneCenter { flight.fly(to: clamped) }
        }
    }

    private func reclamp() {
        let screen = screenGeometry()
        flight.place(at: PerchPlanner.clamp(flight.droneCenter, droneSize: DronePanel.droneSize, screen: screen))
    }
}

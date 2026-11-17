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
    private var dragSamples: [Fling.Sample] = []
    private var lastMouse: (point: CGPoint, time: TimeInterval)?
    private var isFullscreen = false
    private var ticks = 0
    private var idleAnimator = IdleAnimator()
    private var nextGestureAt = Date().addingTimeInterval(10)
    private var chasePolicy = ChasePolicy()
    private var chaseUntil: Date?
    private var chaseReturn: CGPoint?
    private var lastChaseStep = Date.distantPast
    private var lastCursorSpeed: Double = 0
    private var recentSpeeds: [(time: TimeInterval, speed: Double)] = []
    private var startleCooldownUntil = Date.distantPast
    private var petDetector = PetDetector()
    private var petCalmUntil = Date.distantPast
    private var pointingAt: CGPoint?
    let pointer = PointerOverlay()
    private let chaseEarliest = Date().addingTimeInterval(300)
    var chattiness: () -> Chattiness = { .normal }
    private(set) var isHidden = false
    private var hiddenEdge: ScreenEdge?
    private var lastVisibleCenter: CGPoint?

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
            case .wakeUp:
                takeOff()
                model.play(.wiggle)
            default: rest.append(effect)
            }
        }
        return rest
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        let screen = screenGeometry()
        if hidden {
            let edge = ScreenEdge.allCases.randomElement() ?? .right
            hiddenEdge = edge
            lastVisibleCenter = flight.isMoving ? flight.target : flight.droneCenter
            if machine.state == .sleeping { send(.userActive) }
            let exit = PerchPlanner.exitPoint(from: flight.droneCenter, edge: edge, droneSize: DronePanel.droneSize, screen: screen)
            panel.ignoresMouseEvents = true
            cruise(to: exit) { [weak self] in
                guard let self, isHidden else { return }
                panel.orderOut(nil)
            }
        } else {
            let target = PerchPlanner.clamp(lastVisibleCenter ?? flight.droneCenter, droneSize: DronePanel.droneSize, screen: screen)
            let start = PerchPlanner.exitPoint(from: target, edge: hiddenEdge ?? .right, droneSize: DronePanel.droneSize, screen: screen)
            flight.place(at: start)
            panel.orderFrontRegardless()
            nextWanderAt = Date().addingTimeInterval(.random(in: Self.wanderInterval))
            cruise(to: target) { [weak self] in self?.model.play(.wiggle) }
        }
    }

    func setQuiet(_ quiet: Bool) {
        send(.quietChanged(quiet))
    }

    func ensureBubbleFits() {
        guard !isHidden else { return }
        let center = flight.isMoving ? flight.target : flight.droneCenter
        let safe = PerchPlanner.bubbleSafeCenter(center, panelSize: DronePanel.size, droneOffset: DronePanel.droneCenterOffset, screen: screenGeometry())
        guard safe != center else { return }
        flight.fly(to: safe)
    }

    var isMouseOverBubble: Bool {
        guard let rect = model.bubbleRect else { return false }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        return rect.contains(CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY))
    }

    func revealForCapture() {
        panel.alphaValue = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, isFullscreen else { return }
            panel.animator().alphaValue = 0.25
        }
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
        guard !isHidden else { return }
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
        lifeGestures(now)
        if chaseUntil == nil, machine.canWander, !isHidden, now >= nextWanderAt, now >= dragLockUntil, model.bubble == nil, dragStart == nil, !flight.isMoving {
            nextWanderAt = now.addingTimeInterval(.random(in: Self.wanderInterval))
            let screen = ScreenEnvironment.currentScreen()
            var rng = SystemRandomNumberGenerator()
            let spot = PerchPlanner.nextSpot(screen: screen, droneSize: DronePanel.droneSize, cursor: ScreenEnvironment.cursor(),
                                             windowTops: ScreenEnvironment.windowTops(on: screen), using: &rng)
            cruise(to: spot.point)
        }
    }

    private func hitTick() {
        guard !isHidden else {
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
            return
        }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let now = ProcessInfo.processInfo.systemUptime
        let speed = lastMouse.map { hypot(mouse.x - $0.point.x, mouse.y - $0.point.y) / max(0.001, now - $0.time) } ?? 0
        lastMouse = (mouse, now)
        lastCursorSpeed = speed
        recentSpeeds.append((now, speed))
        recentSpeeds.removeAll { now - $0.time > 1.5 }
        updateEyes(pointingAt ?? mouse)
        if chaseUntil != nil { updateChase(mouse) }

        let local = CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
        let shape = HitShape(droneRect: DronePanel.droneRect, bubbleRect: model.bubbleRect)
        let overDrone = frame.contains(mouse) && shape.contains(local)
        if dragStart == nil {
            let ignore = !overDrone
            if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
        }
        updatePetting(mouse: mouse, now: now, overDrone: overDrone)

        if !overDrone, Date() >= petCalmUntil, speed > Self.dodgeCursorSpeed, Date() >= startleCooldownUntil,
           !machine.quiet, !machine.fullscreen, model.bubble == nil,
           hypot(mouse.x - flight.droneCenter.x, mouse.y - flight.droneCenter.y) < 150,
           machine.state == .hover || machine.state == .flying {
            startleCooldownUntil = Date().addingTimeInterval(5)
            model.play(.startle)
        }

        guard chaseUntil == nil, !overDrone, Date() >= petCalmUntil, speed > Self.dodgeCursorSpeed, machine.canWander, model.bubble == nil, dragStart == nil,
              !flight.isMoving, Date() >= dodgeCooldownUntil, Date() >= dragLockUntil else { return }
        if let target = PerchPlanner.dodge(droneCenter: flight.droneCenter, cursor: mouse, screen: screenGeometry(), droneSize: DronePanel.droneSize) {
            dodgeCooldownUntil = Date().addingTimeInterval(5)
            cruise(to: target)
        }
    }

    private func handleDrag(_ phase: DragPhase) {
        let mouse = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        switch phase {
        case .changed:
            if dragStart == nil {
                clearPointer()
                if machine.state == .flying { send(.arrived) }
                flight.stop()
                dragStart = (mouse, flight.droneCenter)
                dragSamples = []
            }
            guard let start = dragStart else { return }
            dragSamples.append(Fling.Sample(time: now, point: mouse))
            dragSamples.removeAll { now - $0.time > 0.3 }
            flight.place(at: CGPoint(x: start.center.x + mouse.x - start.mouse.x, y: start.center.y + mouse.y - start.mouse.y))
        case .ended:
            dragStart = nil
            dragLockUntil = Date().addingTimeInterval(Self.dragLock)
            let velocity = Fling.releaseVelocity(dragSamples, now: now)
            dragSamples = []
            let screen = screenGeometry()
            if let plan = Fling.plan(from: flight.droneCenter, velocity: velocity) {
                let target = PerchPlanner.clamp(plan.target, droneSize: DronePanel.droneSize, screen: screen)
                let fromLeft = plan.velocity.dx >= 0
                flight.fling(velocity: plan.velocity, to: target) { [weak self] in
                    self?.model.play(.steady(fromLeft: fromLeft))
                }
                return
            }
            let clamped = PerchPlanner.clamp(flight.droneCenter, droneSize: DronePanel.droneSize, screen: screen)
            if clamped != flight.droneCenter { flight.fly(to: clamped) }
        }
    }

    private func reclamp() {
        let screen = screenGeometry()
        flight.place(at: PerchPlanner.clamp(flight.droneCenter, droneSize: DronePanel.droneSize, screen: screen))
    }

    private func lifeGestures(_ now: Date) {
        let peakSpeed = recentSpeeds.map(\.speed).max() ?? 0
        guard !petDetector.isPetting, now >= petCalmUntil else { return }
        if chaseUntil == nil, now >= chaseEarliest, now >= dragLockUntil, lastCursorSpeed > 20, NSEvent.pressedMouseButtons == 0,
           !flight.isMoving, dragStart == nil, model.bubble == nil,
           chasePolicy.shouldChase(now: now, chattiness: chattiness(), cursorSpeed: peakSpeed,
                                   canWander: machine.canWander, bubbleVisible: model.bubble != nil) {
            startChase(now)
            return
        }
        guard machine.state == .hover, !machine.quiet, !machine.fullscreen, !flight.isMoving,
              dragStart == nil, chaseUntil == nil, now >= nextGestureAt else { return }
        var rng = SystemRandomNumberGenerator()
        let gesture = idleAnimator.pick(now: now, hour: Calendar.current.component(.hour, from: now), using: &rng)
        model.play(.idle(gesture))
        nextGestureAt = now.addingTimeInterval(IdleAnimator.delay(using: &rng))
    }

    func point(at target: CGPoint, label: String) -> Bool {
        guard !isHidden else { return false }
        if chaseUntil != nil { endChase(returnHome: false) }
        let screen = NSScreen.screens.first { $0.frame.contains(target) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return false }
        let perch = PointerLayout.droneSpot(target: target, visibleFrame: visible, droneSize: DronePanel.droneSize)
        let spot = PerchPlanner.bubbleSafeCenter(perch, panelSize: DronePanel.size, droneOffset: DronePanel.droneCenterOffset, screen: screenGeometry())
        pointingAt = target
        pointer.show(target: target, label: label, below: panel)
        flight.fly(to: spot) { [weak self] in
            guard let self, pointingAt == target else { return }
            pointer.showArrow(from: flight.droneCenter)
        }
        return true
    }

    func clearPointer() {
        pointingAt = nil
        pointer.hide()
    }

    private func updatePetting(mouse: CGPoint, now: TimeInterval, overDrone: Bool) {
        let eligible = overDrone && machine.state == .hover && dragStart == nil && !flight.isMoving
        for event in petDetector.update(x: mouse.x, time: now, overDrone: eligible, buttonDown: NSEvent.pressedMouseButtons != 0) {
            switch event {
            case .started:
                petCalmUntil = .distantFuture
                model.petting = true
                hum.setPurring(!machine.quiet)
            case .heart:
                model.play(.heart)
            case .ended:
                petCalmUntil = Date().addingTimeInterval(1)
                model.petting = false
                hum.setPurring(false)
            }
        }
    }

    private func updateEyes(_ mouse: CGPoint) {
        let offset = EyeTracker.offset(droneCenter: flight.droneCenter, cursor: mouse)
        if abs(offset.dx - model.eyeOffset.dx) > 0.1 || abs(offset.dy - model.eyeOffset.dy) > 0.1 {
            model.eyeOffset = offset
        }
    }

    private func startChase(_ now: Date) {
        chaseReturn = flight.droneCenter
        chaseUntil = now.addingTimeInterval(4)
        lastChaseStep = .distantPast
        send(.wanderStarted)
    }

    private func updateChase(_ mouse: CGPoint) {
        guard let until = chaseUntil else { return }
        let aborted = isHidden || dragStart != nil || model.bubble != nil || machine.state != .flying
        if aborted || Date() >= until {
            endChase(returnHome: !aborted || machine.state == .flying)
            return
        }
        guard Date().timeIntervalSince(lastChaseStep) >= 0.3 else { return }
        lastChaseStep = Date()
        let target = PerchPlanner.clamp(CGPoint(x: mouse.x + 120, y: mouse.y + 80), droneSize: DronePanel.droneSize, screen: screenGeometry())
        flight.fly(to: target)
    }

    private func endChase(returnHome: Bool) {
        chaseUntil = nil
        guard returnHome, let home = chaseReturn, machine.state == .flying else {
            chaseReturn = nil
            return
        }
        chaseReturn = nil
        flight.fly(to: PerchPlanner.clamp(home, droneSize: DronePanel.droneSize, screen: screenGeometry())) { [weak self] in
            self?.send(.arrived)
        }
    }
}

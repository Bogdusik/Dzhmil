import AppKit
import DzhmilCore

@MainActor
final class ProactiveDriver {
    static let key = "dzhmil.proactive"
    static let tickInterval: TimeInterval = 20
    static let activeIdleLimit: TimeInterval = 300
    static let sessionBreakIdle: TimeInterval = 600

    private unowned let companion: Companion
    private var scheduler: ProactiveScheduler
    private var activeSince: Date?
    private var timer: Timer?
    private var running = false

    init(companion: Companion) {
        self.companion = companion
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(ProactiveScheduler.self, from: data) {
            scheduler = s
        } else {
            scheduler = ProactiveScheduler()
        }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func fire(_ trigger: ProactiveTrigger) {
        Task { await speak(trigger) }
    }

    private func tick() {
        guard !running else { return }
        running = true
        Task {
            defer { running = false }
            await evaluate()
        }
    }

    private func evaluate() async {
        let now = Date()
        let idle = ScreenEnvironment.secondsSinceUserInput()
        if idle >= Self.sessionBreakIdle {
            activeSince = nil
        } else if idle < Self.activeIdleLimit, activeSince == nil {
            activeSince = now
        }

        let machine = companion.director.machine
        let busy = isBusy
        let battery = SystemMetrics.battery()
        let context = ProactiveContext(now: now, calendar: .current, activeSince: activeSince, isUserActive: idle < Self.activeIdleLimit,
                                       batteryPercent: battery.percent, isCharging: battery.charging,
                                       isQuiet: machine.quiet, isFullscreen: machine.fullscreen, isBusy: busy,
                                       isHidden: companion.director.isHidden, dueTimers: await companion.timers.due(now: now))
        let trigger = scheduler.decide(context, chattiness: companion.settings.chattiness)
        save()
        guard let trigger else { return }
        await speak(trigger)
    }

    private var isBusy: Bool {
        let machine = companion.director.machine
        let bubbleBusy = companion.model.bubble != nil && !companion.replyFinished
        return ![DroneState.hover, .flying, .sleeping].contains(machine.state) || bubbleBusy || companion.isListening
    }

    private func speak(_ trigger: ProactiveTrigger) async {
        let phrase: String
        if case .timer = trigger {
            phrase = PhraseWriter.template(trigger, language: companion.language)
        } else {
            phrase = await PhraseWriter.write(trigger, client: companion.client, settings: companion.settings.conversation,
                                              profile: companion.profileStore.load())
        }
        guard !isBusy, !companion.director.isHidden else {
            if case .timer(let label) = trigger { await companion.timers.add(label: label, fireAt: Date()) }
            return
        }
        await companion.conversation.noteRemark(phrase)
        if trigger.isQuestion || companion.director.machine.state == .sleeping {
            _ = companion.director.send(.userActive)
        }
        companion.say(phrase, asQuestion: trigger.isQuestion)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(scheduler) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

import AppKit
import DzhmilCore

@MainActor
final class UpdateDriver {
    static let key = "dzhmil.updates"
    static let tickInterval: TimeInterval = 60
    static let launchDelay: TimeInterval = 20

    let current: AppVersion
    private(set) var available: Release?
    private unowned let companion: Companion
    private var schedule: UpdateSchedule
    private var timer: Timer?
    private var checking = false

    init(companion: Companion) {
        self.companion = companion
        schedule = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(UpdateSchedule.self, from: $0) } ?? UpdateSchedule()
        var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--current-version"), i + 1 < CommandLine.arguments.count {
            version = CommandLine.arguments[i + 1]
        }
        #endif
        current = AppVersion(version) ?? AppVersion("0")!
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchDelay) { [weak self] in self?.tick() }
    }

    func checkNow() {
        guard !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            let found = await refresh()
            guard !companion.director.machine.pendingConfirmation, !companion.isListening else { return }
            let language = companion.language
            if let available {
                offer(available)
            } else if found {
                companion.say(language.pick("You're on the latest version, \(current).", "У тебя последняя версия, \(current)."))
            } else {
                companion.say(language.pick("I couldn't check for updates. Check your internet.", "Не получилось проверить обновления. Проверь интернет."))
            }
        }
    }

    func openUpdate() {
        guard let available else { return }
        let language = companion.language
        guard NSWorkspace.shared.open(available.page) else {
            companion.say(language.pick("I couldn't open the download page.", "Не получилось открыть страницу загрузки."))
            return
        }
        companion.say(language.pick("I opened the download page. Download the new version, quit me and drag it onto Applications. If macOS asks about my saved key, click Always Allow.",
                                    "Открыл страницу загрузки. Скачай новую версию, закрой меня и перетащи её в «Программы». Если macOS спросит про мой сохранённый ключ, нажми «Разрешать всегда» (Always Allow)."))
    }

    private func tick() {
        guard companion.settings.checkForUpdates, !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            if schedule.isCheckDue(now: Date()) { _ = await refresh() }
            offerIfWelcome()
        }
    }

    private func refresh() async -> Bool {
        do {
            let latest = try await ReleaseFeed.latest()
            schedule.checked(at: Date())
            available = latest.version > current ? latest : nil
            return true
        } catch {
            Log.app.notice("Update check failed: \(String(describing: error), privacy: .public)")
            schedule.failed(at: Date())
            return false
        }
    }

    private func offerIfWelcome() {
        let director = companion.director
        guard companion.settings.checkForUpdates, let available,
              schedule.shouldAsk(about: available.version, current: current, now: Date(), calendar: .current),
              !companion.isBusy, !director.isHidden, !director.machine.quiet, !director.machine.fullscreen,
              ScreenEnvironment.secondsSinceUserInput() < ProactiveDriver.activeIdleLimit else { return }
        offer(available)
    }

    private func offer(_ release: Release) {
        schedule.asked(about: release.version, at: Date())
        if let data = try? JSONEncoder().encode(schedule) { UserDefaults.standard.set(data, forKey: Self.key) }
        _ = companion.director.send(.userActive)
        companion.offerUpdate(companion.language.pick("A new version of me is out: \(release.version). Will you update me?",
                                                      "Вышла моя новая версия \(release.version). Обновишь меня?"))
    }
}

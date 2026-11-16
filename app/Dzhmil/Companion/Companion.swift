import AppKit
import SwiftUI
import DzhmilCore

final class SettingsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AppSettings
    init(_ v: AppSettings) { value = v }
    var current: AppSettings {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

@MainActor
final class Companion {
    static let bubbleLinger: Duration = .seconds(6)
    static let pressDelay: Duration = .milliseconds(250)

    let director = DroneDirector()
    let keychain = KeychainStore()
    let profileStore = ProfileStore()
    let timers = TimerStore()
    let settingsBox = SettingsBox(AppSettings.load(from: .standard))
    let speaker = Speaker()
    let transcriber = Transcriber()

    private(set) lazy var confirmer = BubbleConfirmer(director: director)
    private(set) lazy var client = URLSessionClaudeClient(apiKey: { [keychain] in keychain.read() })
    private(set) lazy var conversation: Conversation = {
        let box = settingsBox
        let profile = profileStore
        return Conversation(client: client,
                            executor: ToolExecutor(tools: MacToolbox.all(timers: timers), confirmer: confirmer),
                            settings: { box.current.conversation },
                            profile: { profile.load() })
    }()

    private(set) lazy var proactive = ProactiveDriver(companion: self)
    private let recorder = AudioRecorder()
    private var gate = PushToTalkGate()
    private var turnTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var pressTask: Task<Void, Never>?
    private var pressStartedPTT = false
    private var autoStopTimer: Timer?

    var onboardingSubmit: ((String) -> Void)?

    var settings: AppSettings {
        get { settingsBox.current }
        set {
            settingsBox.current = newValue
            newValue.save(to: .standard)
            applySettings()
        }
    }

    var model: CompanionViewModel { director.model }

    func start() {
        model.bubbleContent = { [weak self] bubble in
            AnyView(BubbleView(bubble: bubble,
                               onAnswer: { self?.confirmer.resolve($0) },
                               onSubmit: { self?.submit($0, from: bubble) },
                               onReply: { self?.replyToQuestion() },
                               onLater: { self?.closeBubble() },
                               onCancel: { self?.closeBubble() }))
        }
        model.onDoubleClick = { [weak self] in self?.openTextInput() }
        model.onPressBegan = { [weak self] in self?.pressBegan() }
        model.onPressEnded = { [weak self] in self?.pressEnded() }
        confirmer.onShow = { [weak self] in self?.bubbleShown() }

        director.start()
        applySettings()
        HotkeyBindings.install(onDown: { [weak self] in self?.pttDown() }, onUp: { [weak self] in self?.pttUp() })
        Task.detached(priority: .utility) { [transcriber] in try? await transcriber.prepare() }
        proactive.start()
    }

    func applySettings() {
        let s = settings
        speaker.enabled = s.voiceEnabled
        speaker.volume = Float(s.voiceVolume)
        director.hum.enabled = s.propellerSound
    }

    func pttDown() {
        guard !gate.isDown, !director.isHidden else { return }
        switch AVAudioPermission.status {
        case .denied:
            say("Мне нужен доступ к микрофону. Открой Системные настройки, раздел Конфиденциальность, Микрофон.")
            return
        case .unknown:
            Task {
                if await AudioRecorder.requestPermission() {
                    say("Спасибо! Теперь зажми клавишу ещё раз и говори.")
                } else {
                    say("Без микрофона я не услышу. Можно написать мне: дважды кликни по мне.")
                }
            }
            return
        case .granted:
            break
        }

        hideTask?.cancel()
        if !director.machine.pendingConfirmation { model.bubble = nil }
        perform(director.send(.pttDown))
        gate.down(at: Date())
        autoStopTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.gate.shouldAutoStop(now: Date()) else { return }
                self.pttUp()
            }
        }
    }

    func pttUp() {
        guard gate.isDown else { return }
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        let outcome = gate.up(at: Date())
        let samples = recorder.isRecording ? recorder.stop() : []
        _ = director.send(.pttUp)
        guard outcome == .accept, !samples.isEmpty else {
            transcriptMissing()
            return
        }
        if !Transcriber.isModelDownloaded {
            model.bubble = .text("Скачиваю слух, это один раз и займёт несколько минут…")
            bubbleShown()
        }
        Task {
            let raw = (try? await transcriber.transcribe(samples)) ?? ""
            if case .text(let t)? = model.bubble, t.hasPrefix("Скачиваю слух") { model.bubble = nil }
            guard let text = TranscriptFilter.clean(raw) else {
                transcriptMissing()
                return
            }
            handleUtterance(text)
        }
    }

    func submitText(_ text: String) {
        if director.machine.pendingConfirmation, let yes = YesNoParser.parse(text) {
            confirmer.resolve(yes)
            return
        }
        perform(director.send(.pttDown))
        perform(director.send(.pttUp))
        startTurn(text)
    }

    func say(_ text: String, asQuestion: Bool = false) {
        hideTask?.cancel()
        model.bubble = asQuestion ? .question(text) : .text(text)
        bubbleShown()
        speaker.enqueue(text)
        if asQuestion {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, case .question? = model.bubble else { return }
                model.bubble = nil
            }
        } else {
            speaker.finish { [weak self] in self?.scheduleHide() }
        }
    }

    func showOnboarding(_ message: String) {
        hideTask?.cancel()
        model.bubble = .onboardingKey(message)
        director.panel.allowsKey = true
        director.panel.makeKey()
        bubbleShown()
    }

    private func perform(_ effects: [BehaviorEffect]) {
        for effect in effects {
            switch effect {
            case .stopSpeech:
                speaker.stop()
            case .cancelConversation:
                turnTask?.cancel()
                turnTask = nil
                let conversation = self.conversation
                Task { await conversation.cancel() }
            case .startRecording:
                do {
                    try recorder.start()
                } catch {
                    gate = PushToTalkGate()
                    _ = director.send(.failed)
                    say("Не получилось включить микрофон.")
                    finishAnimation()
                }
            case .stopRecording:
                _ = recorder.stop()
            case .flyToDock, .wakeUp:
                break
            }
        }
    }

    private func transcriptMissing() {
        _ = director.send(.transcriptEmpty)
    }

    private func handleUtterance(_ text: String) {
        if director.machine.pendingConfirmation {
            if let yes = YesNoParser.parse(text) {
                confirmer.resolve(yes)
            } else {
                _ = director.send(.transcriptEmpty)
                speaker.enqueue("Скажи «да» или «нет».")
            }
            return
        }
        startTurn(text)
    }

    private func startTurn(_ text: String) {
        turnTask?.cancel()
        hideTask?.cancel()
        speaker.stop()
        let conversation = self.conversation
        turnTask = Task { [weak self] in
            let stream = await conversation.send(text)
            var reply = ""
            for await event in stream {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .sentence(let s):
                    if director.machine.state == .thinking { _ = director.send(.replyStarted) }
                    reply += reply.isEmpty ? s : " " + s
                    if !director.machine.pendingConfirmation {
                        model.bubble = .text(reply)
                        bubbleShown()
                    }
                    speaker.enqueue(s)
                case .toolStarted, .toolFinished:
                    break
                case .finished(_, let didAct):
                    speaker.finish { [weak self] in
                        guard let self else { return }
                        _ = director.send(.replyFinished(didAct: didAct))
                        if didAct { finishAnimation() }
                        scheduleHide()
                    }
                case .failed(let error):
                    speaker.stop()
                    _ = director.send(.failed)
                    say(error.userMessage)
                    finishAnimation()
                }
            }
        }
    }

    private func finishAnimation() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            _ = self?.director.send(.animationDone)
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.bubbleLinger)
            guard !Task.isCancelled, let self, case .text? = model.bubble else { return }
            model.bubble = nil
        }
    }

    private func bubbleShown() {
        director.ensureBubbleFits()
    }

    private func closeBubble() {
        hideTask?.cancel()
        if case .confirm? = model.bubble { confirmer.resolve(false) }
        model.bubble = nil
        director.panel.allowsKey = false
        director.panel.resignKey()
    }

    private func openTextInput() {
        guard !director.machine.pendingConfirmation else { return }
        hideTask?.cancel()
        model.bubble = .input
        director.panel.allowsKey = true
        director.panel.makeKey()
        bubbleShown()
    }

    private func submit(_ text: String, from bubble: Bubble) {
        director.panel.allowsKey = false
        director.panel.resignKey()
        model.bubble = nil
        if case .onboardingKey = bubble {
            onboardingSubmit?(text)
        } else {
            submitText(text)
        }
    }

    private func replyToQuestion() {
        model.bubble = nil
        pttDown()
    }

    private func pressBegan() {
        pressTask?.cancel()
        pressTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pressDelay)
            guard !Task.isCancelled, let self else { return }
            pressStartedPTT = true
            pttDown()
        }
    }

    private func pressEnded() {
        pressTask?.cancel()
        pressTask = nil
        if pressStartedPTT {
            pressStartedPTT = false
            pttUp()
        }
    }
}

enum AVAudioPermission {
    case granted, denied, unknown

    static var status: AVAudioPermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }
}

import AVFoundation

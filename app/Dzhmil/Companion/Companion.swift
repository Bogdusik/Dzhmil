import AppKit
import AVFoundation
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
    static let downloadNotice = "Скачиваю слух, это один раз и займёт несколько минут…"

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
    private var pendingCancel: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var autoStopTimer: Timer?
    private var utteranceGeneration = 0
    private var answeringConfirmation: Int?

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
    var isListening: Bool { gate.isDown }

    func start() {
        model.bubbleContent = { [weak self] bubble in
            AnyView(BubbleView(bubble: bubble,
                               onAnswer: { self?.confirmer.answerFromButton($0) },
                               onSubmit: { self?.submit($0, from: bubble) },
                               onReply: { self?.replyToQuestion() },
                               onLater: { self?.closeBubble() },
                               onCancel: { self?.closeBubble() }))
        }
        model.onDoubleClick = { [weak self] in self?.openTextInput() }
        confirmer.showBubble = { [weak self] in self?.show($0) }
        director.panel.onResignKey = { [weak self] in
            guard let self, case .input? = model.bubble else { return }
            show(nil)
        }

        director.chattiness = { [weak self] in self?.settings.chattiness ?? .normal }
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

    func checkKey() async -> String? {
        let request = MessagesRequest(model: settings.model, system: "Ответь одним словом.",
                                      messages: [["role": "user", "content": "ping"]], tools: [], effort: "low", maxTokens: 512)
        do {
            for try await _ in client.stream(request) {}
            return nil
        } catch let error as ClaudeError {
            return error.userMessage
        } catch {
            return ClaudeError.network.userMessage
        }
    }

    func profileChanged() {
        let conversation = self.conversation
        Task { await conversation.resetSession() }
    }

    func setHidden(_ hidden: Bool) {
        if hidden {
            if gate.isDown { pttUp() }
            if case .confirm? = model.bubble { confirmer.resolve(false, id: confirmer.currentID) }
            speaker.stop()
            show(nil)
        }
        director.setHidden(hidden)
    }

    func show(_ bubble: Bubble?) {
        hideTask?.cancel()
        model.bubble = bubble
        let panel = director.panel
        switch bubble {
        case .input?, .onboardingKey?:
            panel.allowsKey = true
            panel.makeKey()
        default:
            if panel.allowsKey || panel.isKeyWindow {
                panel.allowsKey = false
                panel.resignKey()
            }
        }
        if bubble != nil { director.ensureBubbleFits() }
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

        utteranceGeneration += 1
        answeringConfirmation = director.machine.pendingConfirmation ? confirmer.currentID : nil
        if answeringConfirmation == nil { show(nil) }
        gate.down(at: Date())
        perform(director.send(.pttDown))
        guard gate.isDown else { return }
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
        guard outcome == .accept, AudioLevel.hasSpeech(samples) else {
            transcriptMissing()
            return
        }
        let generation = utteranceGeneration
        let confirmID = answeringConfirmation
        if !Transcriber.isModelDownloaded, confirmID == nil { show(.text(Self.downloadNotice)) }
        Task {
            let raw: String
            do {
                raw = try await transcriber.transcribe(samples)
            } catch {
                guard generation == utteranceGeneration else { return }
                _ = director.send(.failed)
                say("Не получилось распознать речь. В первый раз мне нужен интернет, чтобы скачать модель.")
                finishAnimation()
                return
            }
            guard generation == utteranceGeneration, !gate.isDown else { return }
            if case .text(Self.downloadNotice)? = model.bubble { show(nil) }
            guard let text = TranscriptFilter.clean(raw) else {
                transcriptMissing()
                return
            }
            handleUtterance(text, confirmID: confirmID)
        }
    }

    func submitText(_ text: String) {
        if director.machine.pendingConfirmation {
            if let yes = YesNoParser.parse(text) {
                confirmer.resolve(yes, id: confirmer.currentID)
            } else {
                speaker.enqueue("Ответь «да» или «нет».")
            }
            return
        }
        utteranceGeneration += 1
        perform(director.send(.textSubmitted))
        startTurn(text)
    }

    func say(_ text: String, asQuestion: Bool = false) {
        show(asQuestion ? .question(text) : .text(text))
        speaker.enqueue(text)
        if asQuestion {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, case .question? = model.bubble else { return }
                show(nil)
            }
        } else {
            speaker.finish { [weak self] in self?.scheduleHide() }
        }
    }

    func showOnboarding(_ message: String) {
        show(.onboardingKey(message))
    }

    func openTextInput() {
        guard !director.machine.pendingConfirmation else { return }
        show(.input)
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
                let previous = pendingCancel
                pendingCancel = Task {
                    await previous?.value
                    await conversation.cancel()
                }
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

    private func handleUtterance(_ text: String, confirmID: Int?) {
        if let confirmID {
            guard confirmer.currentID == confirmID else { return }
            if let yes = YesNoParser.parse(text) {
                confirmer.resolve(yes, id: confirmID)
            } else {
                _ = director.send(.transcriptEmpty)
                speaker.enqueue("Скажи «да» или «нет».")
            }
            return
        }
        if director.machine.pendingConfirmation {
            _ = director.send(.transcriptEmpty)
            return
        }
        startTurn(text)
    }

    private func startTurn(_ text: String) {
        turnTask?.cancel()
        hideTask?.cancel()
        speaker.stop()
        let conversation = self.conversation
        let cancelFirst = pendingCancel
        turnTask = Task { [weak self] in
            await cancelFirst?.value
            let stream = await conversation.send(text)
            var reply = ""
            for await event in stream {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .sentence(let s):
                    if director.machine.state == .thinking { _ = director.send(.replyStarted) }
                    reply += reply.isEmpty ? s : " " + s
                    if !director.machine.pendingConfirmation { show(.text(reply)) }
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
            show(nil)
        }
    }

    private func closeBubble() {
        if case .confirm? = model.bubble { confirmer.resolve(false, id: confirmer.currentID) }
        show(nil)
    }

    private func submit(_ text: String, from bubble: Bubble) {
        show(nil)
        if case .onboardingKey = bubble {
            onboardingSubmit?(text)
        } else {
            submitText(text)
        }
    }

    private func replyToQuestion() {
        show(nil)
        pttDown()
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

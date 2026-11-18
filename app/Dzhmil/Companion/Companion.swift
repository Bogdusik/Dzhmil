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
    static let downloadNotice = "Downloading my hearing. This happens once and takes a few minutes…"
    static let notHeardMessage = "Sorry, I didn't catch that."

    let director = DroneDirector()
    let keychain = KeychainStore()
    let profileStore = ProfileStore()
    let timers = TimerStore(file: TimerStore.defaultFile)
    let settingsBox = SettingsBox(AppSettings.load(from: .standard))
    let speaker = Speaker()
    let transcriber = Transcriber()

    private(set) lazy var confirmer = BubbleConfirmer(director: director)
    private(set) lazy var client = URLSessionClaudeClient(apiKey: { [keychain] in keychain.read() })
    private(set) lazy var conversation: Conversation = {
        let box = settingsBox
        let profile = profileStore
        let beforeCapture: @Sendable () async -> Bool = { [weak self] in
            let shown = await MainActor.run { () -> Bool in
                guard let self, !self.director.isHidden else { return false }
                self.director.revealForCapture()
                self.model.play(.cameraFlash)
                self.show(.text("Looking at your screen…"))
                return true
            }
            guard shown else { return false }
            try? await Task.sleep(for: .milliseconds(400))
            return true
        }
        let pointer: @Sendable (PointRequest) async -> Bool = { [weak self] request in
            await MainActor.run { self?.director.point(at: request.point, label: request.label) ?? false }
        }
        let beforeClipboard: @Sendable () async -> Bool = { [weak self] in
            await MainActor.run { () -> Bool in
                guard let self, !self.director.isHidden else { return false }
                self.show(.text("Looking at what you copied…"))
                return true
            }
        }
        let tools = MacToolbox.all(timers: timers, screen: SCKScreenCapturer(), beforeCapture: beforeCapture, pointer: pointer,
                                   profile: profile, clipboard: PasteboardReader(), beforeClipboard: beforeClipboard)
        return Conversation(client: client,
                            executor: ToolExecutor(tools: tools, confirmer: confirmer),
                            settings: { box.current.conversation },
                            profile: { profile.load() })
    }()
    private(set) lazy var proactive = ProactiveDriver(companion: self)

    private let recorder = AudioRecorder()
    private var gate = PushToTalkGate()
    private var turnTask: Task<Void, Never>?
    private var pendingCancel: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var clickMonitor: Any?
    private(set) var replyFinished = false
    private var autoStopTimer: Timer?
    private var utteranceGeneration = 0
    private var answeringConfirmation: Int?
    private var lastReply: String?

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
        model.onTap = { [weak self] in self?.bubbleClicked(.drone) }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.bubbleClicked(.elsewhere) }
        }
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

    func checkKey() async -> ClaudeError? {
        let request = MessagesRequest(model: settings.model, system: "Answer in one word.",
                                      messages: [["role": "user", "content": "ping"]], tools: [], effort: "low", maxTokens: 512)
        do {
            for try await _ in client.stream(request) {}
            return nil
        } catch let error as ClaudeError {
            Log.app.error("Key check failed: \(String(describing: error), privacy: .public)")
            return error
        } catch {
            return .network
        }
    }

    func profileChanged() {
        let conversation = self.conversation
        Task { await conversation.resetSession() }
    }

    func setHidden(_ hidden: Bool) {
        if hidden {
            utteranceGeneration += 1
            autoStopTimer?.invalidate()
            autoStopTimer = nil
            gate = PushToTalkGate()
            if case .confirm? = model.bubble { confirmer.resolve(false, id: confirmer.currentID) }
            perform(director.send(.interrupted))
            speaker.stop()
            show(nil)
        }
        director.setHidden(hidden)
    }

    func show(_ bubble: Bubble?) {
        hideTask?.cancel()
        replyFinished = false
        model.bubble = bubble
        if bubble == nil { director.clearPointer() }
        let panel = director.panel
        switch bubble {
        case .input?, .onboardingKey?:
            panel.allowsKey = true
            panel.makeKey()
        default:
            panel.allowsKey = false
            if panel.isKeyWindow {
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
        }
        if bubble != nil { director.ensureBubbleFits() }
    }

    func pttDown() {
        guard !gate.isDown, !director.isHidden else { return }
        switch AVAudioPermission.status {
        case .denied:
            say("I need microphone access. Open System Settings → Privacy & Security → Microphone.")
            return
        case .unknown:
            Task {
                if await AudioRecorder.requestPermission() {
                    say("Thanks! Now hold the key again and talk.")
                } else {
                    say("Without the microphone I can't hear you. You can type to me: double-click me.")
                }
            }
            return
        case .granted:
            break
        }

        utteranceGeneration += 1
        answeringConfirmation = director.machine.pendingConfirmation ? confirmer.currentID : nil
        if answeringConfirmation == nil { show(nil) } else { confirmer.startAnswering() }
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
        guard outcome == .accept else {
            transcriptMissing()
            return
        }
        let seconds = Double(samples.count) / 16_000
        Log.app.notice("Voice: \(seconds, format: .fixed(precision: 1))s recorded, peak level \(AudioLevel.peak(samples), format: .fixed(precision: 4)), speech above \(AudioLevel.threshold, format: .fixed(precision: 4))")
        guard AudioLevel.hasSpeech(samples) else {
            notHeard()
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
                Log.app.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                guard generation == utteranceGeneration else { return }
                confirmer.stopAnswering()
                _ = director.send(.failed)
                say("I couldn't recognise that. The first time, I need the internet to download the speech model.")
                finishAnimation()
                return
            }
            guard generation == utteranceGeneration, !gate.isDown else { return }
            if case .text(Self.downloadNotice)? = model.bubble { show(nil) }
            guard let text = TranscriptFilter.clean(raw) else {
                Log.app.notice("Voice: transcript of \(raw.count) characters had nothing usable")
                notHeard()
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
                speaker.enqueue("Please answer yes or no.")
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
            speaker.finish { [weak self] in self?.markReplyFinished() }
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
                    Log.app.error("Microphone failed: \(error.localizedDescription, privacy: .public)")
                    gate = PushToTalkGate()
                    _ = director.send(.failed)
                    say("I couldn't turn the microphone on.")
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
        confirmer.stopAnswering()
        _ = director.send(.transcriptEmpty)
    }

    private func notHeard() {
        transcriptMissing()
        if director.machine.pendingConfirmation {
            speaker.enqueue(Self.notHeardMessage)
        } else {
            say(Self.notHeardMessage)
        }
    }

    private func handleUtterance(_ text: String, confirmID: Int?) {
        confirmer.stopAnswering()
        if let confirmID {
            guard confirmer.currentID == confirmID else { return }
            if let yes = YesNoParser.parse(text) {
                confirmer.resolve(yes, id: confirmID)
            } else {
                _ = director.send(.transcriptEmpty)
                speaker.enqueue("Say yes or no.")
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
        director.clearPointer()
        speaker.stop()
        let conversation = self.conversation
        let cancelFirst = pendingCancel
        turnTask = Task { [weak self] in
            await cancelFirst?.value
            let stream = await conversation.send(text)
            var reply = ""
            var ended = false
            var emotion: Emotion?
            for await event in stream {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .sentence(let s):
                    if director.machine.state == .thinking { _ = director.send(.replyStarted) }
                    reply += reply.isEmpty ? s : " " + s
                    if !director.machine.pendingConfirmation { show(.text(reply)) }
                    let pending = emotion
                    emotion = nil
                    speaker.enqueue(s, onStart: pending.map { e in { [weak self] in self?.model.play(.emotion(e)) } })
                case .emotion(let e):
                    emotion = e
                case .toolStarted, .toolFinished:
                    if let e = emotion { model.play(.emotion(e)) }
                    emotion = nil
                case .finished(_, let didAct):
                    if let e = emotion { model.play(.emotion(e)) }
                    emotion = nil
                    ended = true
                    if !reply.isEmpty { lastReply = reply }
                    speaker.finish { [weak self] in
                        guard let self else { return }
                        _ = director.send(.replyFinished(didAct: didAct))
                        if didAct { finishAnimation() }
                        if reply.isEmpty, case .text? = model.bubble { show(nil) } else { markReplyFinished() }
                    }
                case .failed(let error):
                    ended = true
                    speaker.stop()
                    _ = director.send(.failed)
                    say(error.userMessage)
                    finishAnimation()
                }
            }
            guard let self, !ended, !Task.isCancelled else { return }
            perform(director.send(.interrupted))
        }
    }

    private func finishAnimation() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            _ = self?.director.send(.animationDone)
        }
    }

    private func markReplyFinished() {
        guard case .text? = model.bubble else { return }
        replyFinished = true
    }

    private func bubbleClicked(_ click: BubbleClick) {
        if BubbleRecall.shouldRecall(bubbleVisible: model.bubble != nil, hasLastReply: lastReply != nil, click: click), let lastReply {
            show(.text(lastReply))
            markReplyFinished()
            return
        }
        let isReply: Bool
        if case .text? = model.bubble { isReply = true } else { isReply = false }
        guard BubbleDismissal.shouldDismiss(isReply: isReply, finished: replyFinished, click: click) else { return }
        show(nil)
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

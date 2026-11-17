import AVFoundation
import DzhmilCore

@MainActor
final class Speaker: NSObject {
    private let synth = AVSpeechSynthesizer()
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let voices = AVSpeechSynthesisVoice.speechVoices().map {
            VoiceInfo(identifier: $0.identifier, language: $0.language, quality: $0.quality.rawValue, name: $0.name)
        }
        return VoiceSelector.pickEnglish(from: voices).flatMap { AVSpeechSynthesisVoice(identifier: $0.identifier) }
    }()
    private var tracker = SpeechTracker<() -> Void>()
    private var startedBatch = false
    private var startActions: [ObjectIdentifier: () -> Void] = [:]

    var volume: Float = 0.8
    var enabled = true
    var onStart: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    var isSpeaking: Bool { tracker.isSpeaking }

    func enqueue(_ sentence: String, onStart: (() -> Void)? = nil) {
        guard enabled else {
            onStart?()
            return
        }
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = voice
        utterance.rate = 0.52
        utterance.volume = volume
        if let onStart { startActions[ObjectIdentifier(utterance)] = onStart }
        tracker.started()
        synth.speak(utterance)
    }

    func finish(then action: @escaping () -> Void) {
        guard let now = tracker.whenIdle(action) else { return }
        startedBatch = false
        now()
    }

    func stop() {
        tracker.reset()
        startedBatch = false
        startActions = [:]
        synth.stopSpeaking(at: .immediate)
    }

    fileprivate func didStart(_ id: ObjectIdentifier) {
        startActions.removeValue(forKey: id)?()
        guard !startedBatch else { return }
        startedBatch = true
        onStart?()
    }

    fileprivate func didFinishOne(_ id: ObjectIdentifier) {
        startActions.removeValue(forKey: id)
        let actions = tracker.finishedOne()
        if !tracker.isSpeaking { startedBatch = false }
        for action in actions { action() }
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.didStart(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.didFinishOne(id) }
    }
}

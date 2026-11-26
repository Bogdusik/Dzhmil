import AVFoundation
import DzhmilCore

@MainActor
final class Speaker: NSObject {
    private let synth = AVSpeechSynthesizer()
    private var voices: [Language: AVSpeechSynthesisVoice] = [:]
    private var tracker = SpeechTracker<() -> Void>()
    private var startedBatch = false
    private var startActions: [ObjectIdentifier: () -> Void] = [:]

    static let hornetPitch: Float = 0.65

    var language = Language.english
    var pitch: Float = 1
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
        let utterance = AVSpeechUtterance(string: SpeechText.forSpeech(sentence, language: language))
        utterance.voice = voice(for: language)
        utterance.rate = 0.52
        utterance.pitchMultiplier = pitch
        utterance.volume = volume
        if let onStart { startActions[ObjectIdentifier(utterance)] = onStart }
        tracker.started()
        synth.speak(utterance)
    }

    private func voice(for language: Language) -> AVSpeechSynthesisVoice? {
        if let voice = voices[language] { return voice }
        let installed = AVSpeechSynthesisVoice.speechVoices().map {
            VoiceInfo(identifier: $0.identifier, language: $0.language, quality: $0.quality.rawValue, name: $0.name)
        }
        let voice = VoiceSelector.pick(for: language, from: installed).flatMap { AVSpeechSynthesisVoice(identifier: $0.identifier) }
            ?? AVSpeechSynthesisVoice(language: language.pick("en-GB", "ru-RU"))
        voices[language] = voice
        return voice
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

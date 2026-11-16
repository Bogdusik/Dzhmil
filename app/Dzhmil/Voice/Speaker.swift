import AVFoundation
import DzhmilCore

@MainActor
final class Speaker: NSObject {
    private let synth = AVSpeechSynthesizer()
    private lazy var voices: [VoiceInfo] = AVSpeechSynthesisVoice.speechVoices().map {
        VoiceInfo(identifier: $0.identifier, language: $0.language, quality: $0.quality.rawValue, name: $0.name)
    }
    private var pending = 0
    private var startedBatch = false
    private var whenIdle: (() -> Void)?

    var volume: Float = 0.8
    var enabled = true
    var onStart: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    var isSpeaking: Bool { pending > 0 }

    func enqueue(_ sentence: String) {
        guard enabled else { return }
        let language = LanguageGuess.guess(sentence)
        let utterance = AVSpeechUtterance(string: SpeechText.forSpeech(sentence, language: language))
        if let v = VoiceSelector.pick(language: language, from: voices) {
            utterance.voice = AVSpeechSynthesisVoice(identifier: v.identifier)
        }
        utterance.rate = 0.52
        utterance.volume = volume
        pending += 1
        synth.speak(utterance)
    }

    func finish(then action: @escaping () -> Void) {
        if pending == 0 {
            startedBatch = false
            action()
        } else {
            whenIdle = action
        }
    }

    func stop() {
        whenIdle = nil
        pending = 0
        startedBatch = false
        synth.stopSpeaking(at: .immediate)
    }

    fileprivate func didStart() {
        guard !startedBatch else { return }
        startedBatch = true
        onStart?()
    }

    fileprivate func didFinishOne() {
        guard pending > 0 else { return }
        pending -= 1
        guard pending == 0, let action = whenIdle else { return }
        whenIdle = nil
        startedBatch = false
        action()
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.didStart() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.didFinishOne() }
    }
}

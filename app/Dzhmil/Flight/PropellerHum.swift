import AVFoundation
import DzhmilCore

@MainActor
final class PropellerHum {
    private let engine = AVAudioEngine()
    private let synth = PropellerSynth()
    private var node: AVAudioSourceNode?

    var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            enabled ? start() : stop()
        }
    }

    func setIntensity(_ x: Double) {
        synth.setTarget(enabled ? Float(0.012 + min(1, max(0, x)) * 0.02) : 0)
    }

    private func start() {
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let source = AVAudioSourceNode(renderBlock: synth.renderBlock(sampleRate: rate))
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        node = source
        try? engine.start()
        setIntensity(0)
    }

    private func stop() {
        engine.stop()
        if let node { engine.detach(node) }
        node = nil
    }
}

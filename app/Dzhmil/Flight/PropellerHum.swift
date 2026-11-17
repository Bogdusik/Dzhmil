import AVFoundation
import DzhmilCore

@MainActor
final class PropellerHum {
    private let engine = AVAudioEngine()
    private let synth = PropellerSynth()
    private var node: AVAudioSourceNode?
    private var purring = false
    private var stopTask: Task<Void, Never>?

    var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            if enabled { start() } else if !purring { stop() }
            setIntensity(0)
        }
    }

    func setPurring(_ on: Bool) {
        guard on != purring else { return }
        purring = on
        synth.setPurr(on)
        stopTask?.cancel()
        if on {
            start()
        } else if !enabled {
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, !purring, !enabled else { return }
                stop()
            }
        }
    }

    func setIntensity(_ x: Double) {
        synth.setTarget(enabled ? Float(0.012 + min(1, max(0, x)) * 0.02) : 0)
    }

    private func start() {
        guard node == nil else { return }
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let source = AVAudioSourceNode(renderBlock: synth.renderBlock(sampleRate: rate))
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        node = source
        try? engine.start()
    }

    private func stop() {
        engine.stop()
        if let node { engine.detach(node) }
        node = nil
    }
}

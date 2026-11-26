import AVFoundation
import DzhmilCore

@MainActor
final class HornetSound {
    let synth = HornetSynth()
    var enabled = true
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var stopTask: Task<Void, Never>?

    func start() {
        stopTask?.cancel()
        guard enabled, node == nil else { return }
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let source = AVAudioSourceNode(renderBlock: synth.renderBlock(sampleRate: rate))
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        node = source
        try? engine.start()
    }

    func stop() {
        synth.setThrottle(0)
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, let node else { return }
            engine.stop()
            engine.detach(node)
            self.node = nil
        }
    }
}

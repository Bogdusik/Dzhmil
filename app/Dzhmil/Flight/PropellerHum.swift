import AVFoundation

@MainActor
final class PropellerHum {
    private final class Synth: @unchecked Sendable {
        let lock = NSLock()
        var amplitude: Float = 0
        var target: Float = 0
        var phase: Float = 0
        var noise: Float = 0
        var seed: UInt32 = 0x12345678

        func setTarget(_ t: Float) { lock.withLock { target = t } }

        func render(_ frames: Int, _ buffers: UnsafeMutableAudioBufferListPointer, sampleRate: Float) {
            let goal = lock.withLock { target }
            for frame in 0..<frames {
                amplitude += (goal - amplitude) * 0.0005
                seed = seed &* 1664525 &+ 1013904223
                let white = Float(Int32(bitPattern: seed)) / Float(Int32.max)
                noise += (white - noise) * 0.08
                phase += 180 / sampleRate
                if phase > 1 { phase -= 1 }
                let saw = phase * 2 - 1
                let sample = (noise * 0.6 + saw * 0.25) * amplitude
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
        }
    }

    private let engine = AVAudioEngine()
    private let synth = Synth()
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
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = Float(format.sampleRate)
        let synth = self.synth
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            synth.render(Int(frameCount), UnsafeMutableAudioBufferListPointer(audioBufferList), sampleRate: sampleRate)
            return noErr
        }
        let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: mono)
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

import AVFoundation

public enum AudioCapture {
    public enum CaptureError: Error { case converter }

    public final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [Float] = []

        public init() {}

        func append(_ p: UnsafeBufferPointer<Float>) {
            lock.withLock { samples.append(contentsOf: p) }
        }

        public func take() -> [Float] {
            lock.withLock {
                defer { samples = [] }
                return samples
            }
        }
    }

    private final class Converter: @unchecked Sendable {
        let converter: AVAudioConverter
        let output: AVAudioFormat
        let ratio: Double

        init(_ converter: AVAudioConverter, _ output: AVAudioFormat, _ ratio: Double) {
            self.converter = converter
            self.output = output
            self.ratio = ratio
        }
    }

    public static func tapBlock(inputFormat: AVAudioFormat, sink: Sink) throws -> AVAudioNodeTapBlock {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: output) else { throw CaptureError.converter }
        return makeBlock(Converter(converter, output, 16_000 / inputFormat.sampleRate), sink)
    }

    private static func makeBlock(_ box: Converter, _ sink: Sink) -> AVAudioNodeTapBlock {
        { @Sendable pcm, _ in
            let capacity = AVAudioFrameCount(Double(pcm.frameLength) * box.ratio + 64)
            guard let out = AVAudioPCMBuffer(pcmFormat: box.output, frameCapacity: capacity) else { return }
            nonisolated(unsafe) var fed = false
            var error: NSError?
            box.converter.convert(to: out, error: &error) { _, status in
                if fed {
                    status.pointee = .noDataNow
                    return nil
                }
                fed = true
                status.pointee = .haveData
                return pcm
            }
            if let channel = out.floatChannelData?[0], out.frameLength > 0 {
                sink.append(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
            }
        }
    }
}

public final class PropellerSynth: @unchecked Sendable {
    private let lock = NSLock()
    private var target: Float = 0
    private var amplitude: Float = 0
    private var phase: Float = 0
    private var noise: Float = 0
    private var seed: UInt32 = 0x1234_5678

    public init() {}

    public func setTarget(_ value: Float) {
        lock.withLock { target = value }
    }

    public func renderBlock(sampleRate: Double) -> AVAudioSourceNodeRenderBlock {
        let rate = Float(sampleRate)
        return { @Sendable [self] _, _, frameCount, bufferList in
            render(Int(frameCount), UnsafeMutableAudioBufferListPointer(bufferList), sampleRate: rate)
            return noErr
        }
    }

    private func render(_ frames: Int, _ buffers: UnsafeMutableAudioBufferListPointer, sampleRate: Float) {
        let goal = lock.withLock { target }
        for frame in 0..<frames {
            amplitude += (goal - amplitude) * 0.0005
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Float(Int32(bitPattern: seed)) / Float(Int32.max)
            noise += (white - noise) * 0.08
            phase += 180 / sampleRate
            if phase > 1 { phase -= 1 }
            let sample = (noise * 0.6 + (phase * 2 - 1) * 0.25) * amplitude
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
            }
        }
    }
}

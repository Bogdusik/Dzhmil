import AVFoundation

public final class HornetSynth: @unchecked Sendable {
    private static let hits: [(delay: Float, pitch: Float)] = [(0, 180), (0.16, 260), (0.34, 140), (0.5, 330), (0.68, 95)]

    private let lock = NSLock()
    private var goal: Float = 0
    private var requested = 0
    private var started = 0
    private var throttle: Float = 0
    private var clock: Float = .infinity
    private var phases: (Float, Float, Float) = (0, 0, 0)
    private var rumble: Float = 0
    private var seed: UInt32 = 0x2468_ACE1

    public init() {}

    public func clank() {
        lock.withLock { requested += 1 }
    }

    public func setThrottle(_ value: Float) {
        lock.withLock { goal = min(1, max(0, value)) }
    }

    public func renderBlock(sampleRate: Double) -> AVAudioSourceNodeRenderBlock {
        let rate = Float(sampleRate)
        return { @Sendable [self] _, _, frameCount, bufferList in
            render(Int(frameCount), UnsafeMutableAudioBufferListPointer(bufferList), sampleRate: rate)
            return noErr
        }
    }

    private func render(_ frames: Int, _ buffers: UnsafeMutableAudioBufferListPointer, sampleRate: Float) {
        let (target, wanted) = lock.withLock { (goal, requested) }
        if wanted != started {
            started = wanted
            clock = 0
        }
        for frame in 0..<frames {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Float(Int32(bitPattern: seed)) / Float(Int32.max)
            throttle += (target - throttle) * 0.0004
            if target == 0, throttle < 0.0005 { throttle = 0 }
            rumble += (white - rumble) * (0.02 + 0.1 * throttle)
            phases.0 = (phases.0 + (55 + 45 * throttle) / sampleRate).truncatingRemainder(dividingBy: 1)
            phases.1 = (phases.1 + (900 + 1400 * throttle) / sampleRate).truncatingRemainder(dividingBy: 1)
            let engine = (rumble * 0.9 + (phases.0 * 2 - 1) * 0.18 + sin(2 * Float.pi * phases.1) * 0.05) * throttle * 0.16

            var metal: Float = 0
            if clock < 1.6 {
                for hit in Self.hits where clock >= hit.delay {
                    let age = clock - hit.delay
                    let decay = exp(-age * 14)
                    let ring = sin(2 * Float.pi * hit.pitch * age) + 0.6 * sin(2 * Float.pi * hit.pitch * 2.76 * age) + 0.35 * sin(2 * Float.pi * hit.pitch * 5.4 * age)
                    metal += (ring * 0.07 + white * 0.09 * exp(-age * 40)) * decay
                }
                phases.2 = (phases.2 + (120 + 900 * min(1, clock / 0.9)) / sampleRate).truncatingRemainder(dividingBy: 1)
                metal += sin(2 * Float.pi * phases.2) * 0.03 * max(0, 1 - clock / 1.1)
                clock += 1 / sampleRate
            }
            let sample = min(1, max(-1, engine + metal))
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
            }
        }
    }
}

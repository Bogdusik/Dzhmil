import AVFoundation

@MainActor
final class AudioRecorder {
    enum RecorderError: Error { case noPermission, converter }

    private final class SampleBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [Float] = []
        func append(_ p: UnsafeBufferPointer<Float>) { lock.withLock { samples.append(contentsOf: p) } }
        func take() -> [Float] { lock.withLock { defer { samples = [] }; return samples } }
    }

    private final class ConverterBox: @unchecked Sendable {
        let converter: AVAudioConverter
        let output: AVAudioFormat
        let ratio: Double
        init(_ c: AVAudioConverter, _ o: AVAudioFormat, _ r: Double) { converter = c; output = o; ratio = r }
    }

    private let engine = AVAudioEngine()
    private let buffer = SampleBuffer()
    private(set) var isRecording = false

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start() throws {
        guard !isRecording else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw RecorderError.noPermission }
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else { throw RecorderError.converter }
        let box = ConverterBox(converter, outFormat, 16_000 / inFormat.sampleRate)
        let sink = buffer
        _ = sink.take()
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { pcm, _ in
            let capacity = AVAudioFrameCount(Double(pcm.frameLength) * box.ratio + 64)
            guard let out = AVAudioPCMBuffer(pcmFormat: box.output, frameCapacity: capacity) else { return }
            var fed = false
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
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return buffer.take()
    }
}

import AVFoundation
import DzhmilCore

@MainActor
final class AudioRecorder {
    enum RecorderError: Error { case noPermission }

    private let engine = AVAudioEngine()
    private let sink = AudioCapture.Sink()
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
        let format = input.outputFormat(forBus: 0)
        let block = try AudioCapture.tapBlock(inputFormat: format, sink: sink)
        _ = sink.take()
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: block)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRecording = true
    }

    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return sink.take()
    }
}

import Foundation
@preconcurrency import WhisperKit
import DzhmilCore

actor Transcriber {
    static let defaultModel = "openai_whisper-large-v3-v20240930_turbo_632MB"
    static var modelsDirectory: URL { ProfileStore.defaultDirectory.appendingPathComponent("models", isDirectory: true) }

    private let model: String
    private var pipe: WhisperKit?
    private var loading: Task<Void, Error>?

    init(model: String = Transcriber.defaultModel) {
        self.model = model
    }

    var isReady: Bool { pipe != nil }

    static var isModelDownloaded: Bool {
        let root = modelsDirectory.path
        guard let e = FileManager.default.enumerator(atPath: root) else { return false }
        for case let path as String in e where path.hasSuffix(defaultModel) { return true }
        return false
    }

    func prepare() async throws {
        if pipe != nil { return }
        if let loading {
            try await loading.value
            return
        }
        let task = Task { try await self.load() }
        loading = task
        do {
            try await task.value
        } catch {
            loading = nil
            throw error
        }
    }

    private func load() async throws {
        try FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
        let config = WhisperKitConfig(model: model, downloadBase: Self.modelsDirectory, verbose: false, logLevel: .error, prewarm: true, load: true, download: true)
        pipe = try await WhisperKit(config)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await prepare()
        guard let pipe else { return "" }
        let options = DecodingOptions(task: .transcribe, language: "en", detectLanguage: false, skipSpecialTokens: true, withoutTimestamps: true)
        let results: [TranscriptionResult] = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
    }

    static func loadAudio(path: String) throws -> [Float] {
        try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
    }
}

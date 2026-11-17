import Foundation

public actor TimerStore {
    struct Entry: Codable, Equatable {
        var label: String
        var fireAt: Date
    }

    public static var defaultFile: URL {
        ProfileStore.defaultDirectory.appendingPathComponent("timers.json")
    }

    private let file: URL?
    private var timers: [Entry]

    public init(file: URL? = nil) {
        self.file = file
        timers = file.flatMap { try? JSONDecoder().decode([Entry].self, from: Data(contentsOf: $0)) } ?? []
    }

    public func add(label: String, fireAt: Date) {
        timers.append(Entry(label: label, fireAt: fireAt))
        persist()
    }

    public func due(now: Date) -> [String] {
        let ready = timers.filter { $0.fireAt <= now }
        guard !ready.isEmpty else { return [] }
        timers.removeAll { $0.fireAt <= now }
        persist()
        return ready.map(\.label)
    }

    public var isEmpty: Bool { timers.isEmpty }

    private func persist() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(timers).write(to: file, options: .atomic)
        } catch {
            Log.app.error("Could not save timers: \(error.localizedDescription, privacy: .public)")
        }
    }
}

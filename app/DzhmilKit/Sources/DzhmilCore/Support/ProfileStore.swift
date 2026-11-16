import Foundation

public struct ProfileStore: Sendable {
    public static let template = "Меня зовут Богдан.\nЛюблю FPV-дроны и программирование.\n"

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dzhmil", isDirectory: true)
    }

    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("profile.md") }

    public init(directory: URL = ProfileStore.defaultDirectory) {
        self.directory = directory
    }

    public func load() -> String {
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) { return text }
        try? save(Self.template)
        return Self.template
    }

    public func save(_ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

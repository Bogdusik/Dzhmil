import Foundation

public struct ProfileStore: Sendable {
    public static let template = "Здесь можно написать о себе: как тебя зовут, чем занимаешься, что любишь.\n"

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
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try? save(Self.template)
            return Self.template
        }
        guard let data = try? Data(contentsOf: fileURL) else { return Self.template }
        return String(decoding: data, as: UTF8.self)
    }

    public func save(_ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

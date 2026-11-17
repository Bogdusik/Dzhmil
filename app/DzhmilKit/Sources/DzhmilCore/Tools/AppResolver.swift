import Foundation

public struct AppCandidate: Equatable, Sendable {
    public var name: String
    public var bundleID: String?
    public var url: URL?
    public var isRunning: Bool

    public init(name: String, bundleID: String?, url: URL?, isRunning: Bool) {
        self.name = name
        self.bundleID = bundleID
        self.url = url
        self.isRunning = isRunning
    }
}

public enum AppResolver {
    static let aliases: [String: String] = [
        "chrome": "Google Chrome", "google": "Google Chrome",
        "vs code": "Visual Studio Code", "vscode": "Visual Studio Code", "code": "Visual Studio Code",
        "settings": "System Settings", "system preferences": "System Settings", "preferences": "System Settings",
        "task manager": "Activity Monitor", "zoom": "zoom.us", "iterm": "iTerm",
        "word": "Microsoft Word", "excel": "Microsoft Excel", "powerpoint": "Microsoft PowerPoint",
        "outlook": "Microsoft Outlook", "teams": "Microsoft Teams",
    ]

    static let normalizedAliases = Dictionary(aliases.map { (normalize($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })

    static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasSuffix(".app") { t = String(t.dropLast(4)) }
        t = t.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func resolve(_ query: String, among candidates: [AppCandidate]) -> AppCandidate? {
        let q = normalize(query)
        guard !q.isEmpty else { return nil }
        let normalized = candidates.map { (normalize($0.name), $0) }

        func best(_ matches: [AppCandidate]) -> AppCandidate? {
            matches.first(where: \.isRunning) ?? matches.first
        }

        if let hit = best(normalized.filter { $0.0 == q }.map(\.1)) { return hit }
        if let target = normalizedAliases[q].map(normalize), let hit = best(normalized.filter { $0.0 == target }.map(\.1)) { return hit }
        if let hit = best(normalized.filter { $0.0.hasPrefix(q) }.map(\.1)) { return hit }
        if q.count >= 3, let hit = best(normalized.filter { $0.0.contains(q) }.map(\.1)) { return hit }
        return nil
    }
}

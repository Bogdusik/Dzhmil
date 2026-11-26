import Foundation

public struct AppVersion: Codable, Comparable, CustomStringConvertible, Sendable {
    private let parts: [Int]

    public init?(_ text: String) {
        let numbers = (text.hasPrefix("v") ? text.dropFirst() : Substring(text)).split(separator: ".", omittingEmptySubsequences: false)
        let parsed = numbers.compactMap { $0.allSatisfy { ("0"..."9").contains($0) } ? Int($0) : nil }
        guard !parsed.isEmpty, parsed.count == numbers.count else { return nil }
        parts = parsed
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        !(a < b) && !(b < a)
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}

public struct Release: Equatable, Sendable {
    public let version: AppVersion
    public let page: URL
}

public enum ReleaseFeed {
    public enum Failure: Error, Equatable {
        case status(Int), unreadable
    }

    static let repository = "Bogdusik/Dzhmil"
    static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    private struct Payload: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }

    static func parse(_ data: Data) -> Release? {
        guard let p = try? JSONDecoder().decode(Payload.self, from: data), !p.draft, !p.prerelease,
              let version = AppVersion(p.tag_name),
              let page = URL(string: "https://github.com/\(repository)/releases/tag/\(p.tag_name)") else { return nil }
        return Release(version: version, page: page)
    }

    public static func latest(fetch: @Sendable (URLRequest) async throws -> (Data, Int) = ReleaseFeed.download) async throws -> Release {
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Dzhmil", forHTTPHeaderField: "User-Agent")
        let (data, status) = try await fetch(request)
        guard status == 200 else { throw Failure.status(status) }
        guard let release = parse(data) else { throw Failure.unreadable }
        return release
    }

    @Sendable public static func download(_ request: URLRequest) async throws -> (Data, Int) {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public struct UpdateSchedule: Codable, Equatable, Sendable {
    static let checkEvery: TimeInterval = 6 * 3600
    static let retryAfter: TimeInterval = 15 * 60
    static let askAgainAfter: TimeInterval = 23 * 3600

    private var nextCheckAt: Date?
    private var askedVersion: AppVersion?
    private var askedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case askedVersion, askedAt
    }

    public init() {}

    public func isCheckDue(now: Date) -> Bool {
        nextCheckAt.map { now >= $0 } ?? true
    }

    public mutating func checked(at date: Date) {
        nextCheckAt = date.addingTimeInterval(Self.checkEvery)
    }

    public mutating func failed(at date: Date) {
        nextCheckAt = date.addingTimeInterval(Self.retryAfter)
    }

    public func shouldAsk(about version: AppVersion, current: AppVersion, now: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: now)
        guard version > current, hour >= 7, hour < 23 else { return false }
        guard version == askedVersion, let askedAt else { return true }
        return now.timeIntervalSince(askedAt) >= Self.askAgainAfter
    }

    public mutating func asked(about version: AppVersion, at date: Date) {
        askedVersion = version
        askedAt = date
    }
}

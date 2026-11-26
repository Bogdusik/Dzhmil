import Foundation

public enum Language: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case russian = "ru"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .english: "English"
        case .russian: "Русский"
        }
    }

    public func pick(_ english: String, _ russian: String) -> String {
        switch self {
        case .english: english
        case .russian: russian
        }
    }
}

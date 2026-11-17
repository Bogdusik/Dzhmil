import Foundation

public enum Chattiness: String, Codable, CaseIterable, Sendable {
    case rare, normal, often

    public var minGap: TimeInterval {
        switch self {
        case .rare: 7200
        case .normal: 2700
        case .often: 1200
        }
    }

    public var title: String {
        switch self {
        case .rare: "Редко"
        case .normal: "Нормально"
        case .often: "Часто"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let key = "dzhmil.settings"
    public static let models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
    public static let efforts = ["low", "medium", "high"]

    public var model = "claude-opus-5-5"
    public var effort = "low"
    public var chattiness = Chattiness.normal
    public var voiceEnabled = true
    public var voiceVolume = 0.8
    public var propellerSound = false
    public var launchAtLogin = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? d.model
        effort = (try? c.decodeIfPresent(String.self, forKey: .effort)) ?? d.effort
        chattiness = (try? c.decodeIfPresent(Chattiness.self, forKey: .chattiness)) ?? d.chattiness
        voiceEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .voiceEnabled)) ?? d.voiceEnabled
        voiceVolume = (try? c.decodeIfPresent(Double.self, forKey: .voiceVolume)) ?? d.voiceVolume
        propellerSound = (try? c.decodeIfPresent(Bool.self, forKey: .propellerSound)) ?? d.propellerSound
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
        if !Self.models.contains(model) { model = d.model }
        if !Self.efforts.contains(effort) { effort = d.effort }
    }

    public var conversation: ConversationSettings {
        ConversationSettings(model: model, effort: effort)
    }

    public static func load(from defaults: UserDefaults) -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

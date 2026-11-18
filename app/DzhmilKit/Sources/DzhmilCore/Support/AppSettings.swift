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
        case .rare: "Rarely"
        case .normal: "Normal"
        case .often: "Often"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let key = "dzhmil.settings"
    public static let models = Provider.anthropic.suggestedModels
    public static let efforts = ["low", "medium", "high"]

    public var provider = Provider.anthropic
    public var chosenModels: [String: String] = [:]
    public var effort = "low"
    public var chattiness = Chattiness.normal
    public var voiceEnabled = true
    public var voiceVolume = 0.8
    public var propellerSound = false
    public var launchAtLogin = false

    public init() {}

    public var model: String {
        get {
            let m = chosenModels[provider.rawValue]?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !m.isEmpty, provider != .anthropic || Self.models.contains(m) else { return provider.defaultModel }
            return m
        }
        set { chosenModels[provider.rawValue] = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case provider, chosenModels, model, effort, chattiness, voiceEnabled, voiceVolume, propellerSound, launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        provider = (try? c.decodeIfPresent(Provider.self, forKey: .provider)) ?? d.provider
        chosenModels = (try? c.decodeIfPresent([String: String].self, forKey: .chosenModels)) ?? [:]
        if chosenModels.isEmpty, let legacy = try? c.decodeIfPresent(String.self, forKey: .model) {
            chosenModels[Provider.anthropic.rawValue] = legacy
        }
        effort = (try? c.decodeIfPresent(String.self, forKey: .effort)) ?? d.effort
        chattiness = (try? c.decodeIfPresent(Chattiness.self, forKey: .chattiness)) ?? d.chattiness
        voiceEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .voiceEnabled)) ?? d.voiceEnabled
        voiceVolume = (try? c.decodeIfPresent(Double.self, forKey: .voiceVolume)) ?? d.voiceVolume
        propellerSound = (try? c.decodeIfPresent(Bool.self, forKey: .propellerSound)) ?? d.propellerSound
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
        if !Self.efforts.contains(effort) { effort = d.effort }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(provider, forKey: .provider)
        try c.encode(chosenModels, forKey: .chosenModels)
        try c.encode(effort, forKey: .effort)
        try c.encode(chattiness, forKey: .chattiness)
        try c.encode(voiceEnabled, forKey: .voiceEnabled)
        try c.encode(voiceVolume, forKey: .voiceVolume)
        try c.encode(propellerSound, forKey: .propellerSound)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
    }

    public var conversation: ConversationSettings {
        ConversationSettings(model: model, effort: effort, provider: provider)
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

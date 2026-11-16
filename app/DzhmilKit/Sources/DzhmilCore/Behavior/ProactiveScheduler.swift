import Foundation

public enum ProactiveTrigger: Equatable, Sendable {
    case dailyGreeting
    case breakReminder
    case lowBattery(Int)
    case timer(String)

    public var isQuestion: Bool {
        switch self {
        case .dailyGreeting, .breakReminder: true
        case .lowBattery, .timer: false
        }
    }
}

public struct ProactiveContext: Sendable {
    public var now: Date
    public var calendar: Calendar
    public var activeSince: Date?
    public var isUserActive: Bool
    public var batteryPercent: Int?
    public var isCharging: Bool
    public var isQuiet: Bool
    public var isFullscreen: Bool
    public var isBusy: Bool
    public var dueTimers: [String]

    public init(now: Date, calendar: Calendar, activeSince: Date?, isUserActive: Bool, batteryPercent: Int?, isCharging: Bool,
                isQuiet: Bool, isFullscreen: Bool, isBusy: Bool, dueTimers: [String]) {
        self.now = now
        self.calendar = calendar
        self.activeSince = activeSince
        self.isUserActive = isUserActive
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.isQuiet = isQuiet
        self.isFullscreen = isFullscreen
        self.isBusy = isBusy
        self.dueTimers = dueTimers
    }
}

public struct ProactiveScheduler: Codable, Equatable, Sendable {
    static let breakAfter: TimeInterval = 2 * 3600
    static let lowBatteryThreshold = 15

    var lastSpokeAt: Date?
    var lastGreetingDay: String?
    var lastBreakFor: Date?
    var lowBatteryWarned = false
    var pendingTimers: [String] = []

    public init() {}

    public mutating func decide(_ c: ProactiveContext, chattiness: Chattiness) -> ProactiveTrigger? {
        pendingTimers += c.dueTimers
        if !pendingTimers.isEmpty {
            guard !c.isBusy else { return nil }
            lastSpokeAt = c.now
            return .timer(pendingTimers.removeFirst())
        }

        if c.isCharging { lowBatteryWarned = false }
        if let p = c.batteryPercent, p < Self.lowBatteryThreshold, !c.isCharging, !lowBatteryWarned,
           !c.isBusy, !c.isQuiet, !c.isFullscreen {
            lowBatteryWarned = true
            lastSpokeAt = c.now
            return .lowBattery(p)
        }

        let hour = c.calendar.component(.hour, from: c.now)
        let night = hour >= 23 || hour < 7
        guard !c.isQuiet, !c.isFullscreen, !c.isBusy, !night, c.isUserActive else { return nil }
        if let last = lastSpokeAt, c.now.timeIntervalSince(last) < chattiness.minGap { return nil }

        let day = dayKey(c.now, c.calendar)
        if day != lastGreetingDay {
            lastGreetingDay = day
            lastSpokeAt = c.now
            return .dailyGreeting
        }

        if let since = c.activeSince, c.now.timeIntervalSince(since) >= Self.breakAfter, lastBreakFor != since {
            lastBreakFor = since
            lastSpokeAt = c.now
            return .breakReminder
        }
        return nil
    }

    private func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(d.year ?? 0)-\(d.month ?? 0)-\(d.day ?? 0)"
    }
}

public enum PhraseWriter {
    public static func template(_ t: ProactiveTrigger) -> String {
        switch t {
        case .dailyGreeting: "Привет! Как дела?"
        case .breakReminder: "Ты уже два часа за компьютером. Может, перерыв?"
        case .lowBattery(let n): "Заряд \(n)%. Пора на зарядку, как и мне."
        case .timer(let label): "Напоминаю: \(label)"
        }
    }

    static func reason(_ t: ProactiveTrigger) -> String {
        switch t {
        case .dailyGreeting: "первое приветствие за день, спроси, как у него дела"
        case .breakReminder: "он уже два часа подряд за компьютером, мягко предложи перерыв"
        case .lowBattery(let n): "заряд батареи \(n)% и не заряжается, напомни подключить зарядку"
        case .timer(let label): "сработал таймер, который он просил поставить: «\(label)». Напомни об этом"
        }
    }

    public static func write(_ t: ProactiveTrigger, client: any ClaudeClient, settings: ConversationSettings, profile: String) async -> String {
        let prompt = "[Служебно] Ты сам заговариваешь первым. Повод: \(reason(t)). Скажи одну-две короткие живые фразы, без кавычек."
        let request = MessagesRequest(model: settings.model, system: PromptBuilder.system(profile: profile),
                                      messages: [["role": "user", "content": .string(prompt)]], tools: [], effort: settings.effort, maxTokens: 4096)
        var final: AssistantMessage?
        do {
            for try await event in client.stream(request) {
                if case .message(let m) = event { final = m }
            }
        } catch {
            return template(t)
        }
        let text = final?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return template(t) }
        var splitter = SentenceSplitter()
        var sentences = splitter.feed(text)
        if let rest = splitter.flush() { sentences.append(rest) }
        return sentences.prefix(2).joined(separator: " ")
    }
}

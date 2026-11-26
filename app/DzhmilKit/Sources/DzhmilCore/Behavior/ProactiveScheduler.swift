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
    public var isHidden: Bool
    public var dueTimers: [String]

    public init(now: Date, calendar: Calendar, activeSince: Date?, isUserActive: Bool, batteryPercent: Int?, isCharging: Bool,
                isQuiet: Bool, isFullscreen: Bool, isBusy: Bool, isHidden: Bool = false, dueTimers: [String]) {
        self.now = now
        self.calendar = calendar
        self.activeSince = activeSince
        self.isUserActive = isUserActive
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.isQuiet = isQuiet
        self.isFullscreen = isFullscreen
        self.isBusy = isBusy
        self.isHidden = isHidden
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
        guard !c.isHidden else { return nil }
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
    public static func template(_ t: ProactiveTrigger, language: Language = .english) -> String {
        switch t {
        case .dailyGreeting: language.pick("Hi! How's it going?", "Привет! Как дела?")
        case .breakReminder: language.pick("You've been at the computer for two hours. Time for a break?", "Ты уже два часа за компьютером. Может, перерыв?")
        case .lowBattery(let n): language.pick("Battery at \(n)%. Time to charge, same as me.", "Заряд \(n)%. Пора на зарядку, мне тоже.")
        case .timer(let label): language.pick("Reminder: \(label)", "Напоминание: \(label)")
        }
    }

    static func reason(_ t: ProactiveTrigger) -> String {
        switch t {
        case .dailyGreeting: "first greeting of the day, ask how they are"
        case .breakReminder: "they have been at the computer for two hours straight, gently suggest a break"
        case .lowBattery(let n): "the battery is at \(n)% and not charging, remind them to plug in"
        case .timer(let label): "a timer they asked for has gone off: “\(label)”. Remind them about it"
        }
    }

    public static func write(_ t: ProactiveTrigger, client: any ChatClient, settings: ConversationSettings, profile: String) async -> String {
        let prompt = "[Note] You are speaking first. Reason: \(reason(t)). Say one or two short, lively sentences, without quotes."
        let request = MessagesRequest(model: settings.model, system: PromptBuilder.proactive(profile: profile, language: settings.language),
                                      messages: [["role": "user", "content": .string(prompt)]], tools: [], effort: settings.effort, maxTokens: 4096,
                                      provider: settings.provider)
        var final: AssistantMessage?
        do {
            for try await event in client.stream(request) {
                if case .message(let m) = event { final = m }
            }
        } catch {
            Log.conversation.error("Proactive phrase failed: \(String(describing: error), privacy: .public)")
            return template(t, language: settings.language)
        }
        let raw = final?.text ?? ""
        let text = EmotionFilter.strip(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !ToolMarkup.contains(raw) else { return template(t, language: settings.language) }
        var splitter = SentenceSplitter()
        var sentences = splitter.feed(text)
        if let rest = splitter.flush() { sentences.append(rest) }
        return sentences.prefix(2).joined(separator: " ")
    }
}

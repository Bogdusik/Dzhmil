import Foundation
import Testing
@testable import DzhmilCore

@Suite struct ProactiveSchedulerTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func ctx(_ now: Date, activeSince: Date? = nil, battery: Int? = 80, charging: Bool = false,
             quiet: Bool = false, fullscreen: Bool = false, busy: Bool = false, timers: [String] = []) -> ProactiveContext {
        ProactiveContext(now: now, calendar: calendar, activeSince: activeSince ?? now, isUserActive: true,
                         batteryPercent: battery, isCharging: charging, isQuiet: quiet, isFullscreen: fullscreen,
                         isBusy: busy, dueTimers: timers)
    }

    @Test func greetsOncePerDay() {
        var s = ProactiveScheduler()
        #expect(s.decide(ctx(at(16, 5, 30)), chattiness: .normal) == nil)
        #expect(s.decide(ctx(at(16, 9)), chattiness: .normal) == .dailyGreeting)
        #expect(s.decide(ctx(at(16, 15)), chattiness: .normal) == nil)
        #expect(s.decide(ctx(at(17, 9)), chattiness: .normal) == .dailyGreeting)
    }

    @Test func breakAfterTwoHours() {
        var s = ProactiveScheduler()
        _ = s.decide(ctx(at(16, 8)), chattiness: .normal)
        let since = at(16, 9)
        #expect(s.decide(ctx(at(16, 10, 59), activeSince: since), chattiness: .normal) == nil)
        #expect(s.decide(ctx(at(16, 11, 1), activeSince: since), chattiness: .normal) == .breakReminder)
        #expect(s.decide(ctx(at(16, 13), activeSince: since), chattiness: .normal) == nil)
        let later = at(16, 14)
        #expect(s.decide(ctx(at(16, 16, 1), activeSince: later), chattiness: .normal) == .breakReminder)
    }

    @Test func lowBatteryOncePerDischarge() {
        var s = ProactiveScheduler()
        _ = s.decide(ctx(at(16, 9)), chattiness: .normal)
        #expect(s.decide(ctx(at(16, 9, 1), battery: 14), chattiness: .normal) == .lowBattery(14))
        #expect(s.decide(ctx(at(16, 10), battery: 12), chattiness: .normal) == nil)
        #expect(s.decide(ctx(at(16, 10, 5), battery: 30, charging: true), chattiness: .normal) == nil)
        #expect(s.decide(ctx(at(16, 11), battery: 13), chattiness: .normal) == .lowBattery(13))
    }

    @Test(arguments: [(Chattiness.normal, 44, 46), (.rare, 119, 121), (.often, 19, 21)])
    func gapRespected(_ chattiness: Chattiness, _ tooSoon: Int, _ ok: Int) {
        var s = ProactiveScheduler()
        #expect(s.decide(ctx(at(16, 10)), chattiness: chattiness) == .dailyGreeting)
        let since = at(16, 7)
        let soon = at(16, 10).addingTimeInterval(TimeInterval(tooSoon * 60))
        let later = at(16, 10).addingTimeInterval(TimeInterval(ok * 60))
        #expect(s.decide(ctx(soon, activeSince: since), chattiness: chattiness) == nil)
        #expect(s.decide(ctx(later, activeSince: since), chattiness: chattiness) == .breakReminder)
    }

    @Test func lowBatteryIgnoresGap() {
        var s = ProactiveScheduler()
        _ = s.decide(ctx(at(16, 10)), chattiness: .rare)
        #expect(s.decide(ctx(at(16, 10, 1), battery: 10), chattiness: .rare) == .lowBattery(10))
    }

    @Test func suppressedWhenQuietFullscreenNightOrBusy() {
        for c in [ctx(at(16, 9), quiet: true), ctx(at(16, 9), fullscreen: true), ctx(at(16, 9), busy: true), ctx(at(16, 23, 30))] {
            var s = ProactiveScheduler()
            #expect(s.decide(c, chattiness: .often) == nil)
        }
        var s = ProactiveScheduler()
        _ = s.decide(ctx(at(16, 8)), chattiness: .often)
        #expect(s.decide(ctx(at(16, 23, 30), activeSince: at(16, 20)), chattiness: .often) == nil)
    }

    @Test func timersAlwaysFire() {
        var s = ProactiveScheduler()
        _ = s.decide(ctx(at(16, 9)), chattiness: .rare)
        #expect(s.decide(ctx(at(16, 23, 30), quiet: true, timers: ["чайник"]), chattiness: .rare) == .timer("чайник"))
        #expect(s.decide(ctx(at(16, 23, 31), busy: true, timers: ["окно"]), chattiness: .rare) == nil)
        #expect(s.decide(ctx(at(16, 23, 32)), chattiness: .rare) == .timer("окно"))
    }

    @Test func roundTripsThroughJSON() throws {
        var s = ProactiveScheduler()
        _ = s.decide(ctx(at(16, 9)), chattiness: .normal)
        let data = try JSONEncoder().encode(s)
        var restored = try JSONDecoder().decode(ProactiveScheduler.self, from: data)
        #expect(restored.decide(ctx(at(16, 15)), chattiness: .normal) == nil)
    }
}

@Suite struct PhraseWriterTests {
    let settings = ConversationSettings(model: "claude-haiku-5-5", effort: "low")

    @Test func templates() {
        #expect(PhraseWriter.template(.dailyGreeting) == "Привет! Как дела?")
        #expect(PhraseWriter.template(.breakReminder) == "Ты уже два часа за компьютером. Может, перерыв?")
        #expect(PhraseWriter.template(.lowBattery(12)) == "Заряд 12%. Пора на зарядку, как и мне.")
        #expect(PhraseWriter.template(.timer("чайник")) == "Напоминаю: чайник")
    }

    @Test func fallsBackToTemplateOnError() async {
        let client = FakeClaudeClient([.fail(.network)])
        #expect(await PhraseWriter.write(.dailyGreeting, client: client, settings: settings, profile: "") == "Привет! Как дела?")
    }

    @Test func keepsFirstTwoSentences() async {
        let client = FakeClaudeClient([Fixtures.text("Доброе утро! Как спалось? Я уже проснулся. Ещё")])
        #expect(await PhraseWriter.write(.dailyGreeting, client: client, settings: settings, profile: "") == "Доброе утро! Как спалось?")
        #expect(client.requests.first?.tools.isEmpty == true)
    }

    @Test func emptyReplyFallsBack() async {
        let client = FakeClaudeClient([Fixtures.text("   ")])
        #expect(await PhraseWriter.write(.timer("чайник"), client: client, settings: settings, profile: "") == "Напоминаю: чайник")
    }
}

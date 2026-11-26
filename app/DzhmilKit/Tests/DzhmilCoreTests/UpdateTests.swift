import Foundation
import Testing
@testable import DzhmilCore

@Suite struct AppVersionTests {
    @Test(arguments: [("0.4.0", "0.3.1"), ("v0.3.2", "0.3.1"), ("1.0", "0.9.9"), ("0.10.0", "0.9.0"), ("0.3.1.1", "0.3.1")])
    func newer(_ a: String, _ b: String) throws {
        #expect(try #require(AppVersion(a)) > #require(AppVersion(b)))
    }

    @Test func sameVersionWrittenDifferently() {
        #expect(AppVersion("v1.2") == AppVersion("1.2.0"))
        #expect(AppVersion("v0.4.0")?.description == "0.4.0")
    }

    @Test(arguments: ["", "v", "latest", "0.4.0-beta", "1..2", "1.2.", "../1", "1.-2", "1.2 "])
    func rejectsAnythingElse(_ raw: String) {
        #expect(AppVersion(raw) == nil)
    }
}

@Suite struct ReleaseFeedTests {
    func body(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> Data {
        Data(#"{"tag_name":"\#(tag)","draft":\#(draft),"prerelease":\#(prerelease),"html_url":"https://evil.example/download"}"#.utf8)
    }

    @Test func readsTheTagAndBuildsItsOwnLink() throws {
        let release = try #require(ReleaseFeed.parse(body("v0.4.0")))
        #expect(release.version == AppVersion("0.4.0"))
        #expect(release.page.absoluteString == "https://github.com/Bogdusik/Dzhmil/releases/tag/v0.4.0")
    }

    @Test func ignoresDraftsPrereleasesAndGarbage() {
        #expect(ReleaseFeed.parse(body("v0.4.0", draft: true)) == nil)
        #expect(ReleaseFeed.parse(body("v0.4.0", prerelease: true)) == nil)
        #expect(ReleaseFeed.parse(body("nightly")) == nil)
        #expect(ReleaseFeed.parse(Data("<html>".utf8)) == nil)
        #expect(ReleaseFeed.parse(Data(#"{"message":"Not Found"}"#.utf8)) == nil)
    }

    @Test func asksGitHubForTheLatestRelease() async throws {
        let seen = ProfileBox("")
        let data = body("v0.4.0")
        let release = try await ReleaseFeed.latest { request in
            seen.value = request.url?.absoluteString ?? ""
            return (data, 200)
        }
        #expect(seen.value == "https://api.github.com/repos/Bogdusik/Dzhmil/releases/latest")
        #expect(release.version == AppVersion("0.4.0"))
    }

    @Test(arguments: [403, 404, 500])
    func failsOnAnErrorStatus(_ status: Int) async {
        let data = body("v0.4.0")
        await #expect(throws: ReleaseFeed.Failure.self) { try await ReleaseFeed.latest { _ in (data, status) } }
    }

    @Test func failsOnAnUnreadableAnswer() async {
        await #expect(throws: ReleaseFeed.Failure.self) { try await ReleaseFeed.latest { _ in (Data("{}".utf8), 200) } }
    }
}

@Suite struct UpdateScheduleTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()
    let old = AppVersion("0.3.1")!
    let new = AppVersion("0.4.0")!

    func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 12, day: day, hour: hour))!
    }

    @Test func checksAtStartThenEverySixHours() {
        var s = UpdateSchedule()
        #expect(s.isCheckDue(now: at(1, 9)))
        s.checked(at: at(1, 9))
        #expect(!s.isCheckDue(now: at(1, 14)))
        #expect(s.isCheckDue(now: at(1, 15)))
    }

    @Test func triesAgainSoonerAfterAFailure() {
        var s = UpdateSchedule()
        s.failed(at: at(1, 9))
        #expect(!s.isCheckDue(now: at(1, 9).addingTimeInterval(10 * 60)))
        #expect(s.isCheckDue(now: at(1, 9).addingTimeInterval(16 * 60)))
    }

    @Test func asksOnlyAboutANewerVersion() {
        let s = UpdateSchedule()
        #expect(s.shouldAsk(about: new, current: old, now: at(1, 12), calendar: calendar))
        #expect(!s.shouldAsk(about: old, current: old, now: at(1, 12), calendar: calendar))
        #expect(!s.shouldAsk(about: old, current: new, now: at(1, 12), calendar: calendar))
    }

    @Test func staysQuietAtNight() {
        let s = UpdateSchedule()
        #expect(!s.shouldAsk(about: new, current: old, now: at(1, 23), calendar: calendar))
        #expect(!s.shouldAsk(about: new, current: old, now: at(1, 3), calendar: calendar))
        #expect(s.shouldAsk(about: new, current: old, now: at(1, 7), calendar: calendar))
    }

    @Test func asksAgainTheNextDayButAtOnceForAnotherVersion() {
        var s = UpdateSchedule()
        s.asked(about: new, at: at(1, 12))
        #expect(!s.shouldAsk(about: new, current: old, now: at(1, 20), calendar: calendar))
        #expect(s.shouldAsk(about: new, current: old, now: at(2, 12), calendar: calendar))
        #expect(s.shouldAsk(about: AppVersion("0.5.0")!, current: old, now: at(1, 13), calendar: calendar))
    }

    @Test func remembersOnlyWhatItAsked() throws {
        var s = UpdateSchedule()
        s.checked(at: at(1, 9))
        s.asked(about: new, at: at(1, 9))
        let restored = try JSONDecoder().decode(UpdateSchedule.self, from: JSONEncoder().encode(s))
        #expect(restored.isCheckDue(now: at(1, 10)))
        #expect(!restored.shouldAsk(about: new, current: old, now: at(1, 10), calendar: calendar))
    }
}

@Suite struct UpdateSettingsTests {
    @Test func checksByDefaultAndCanBeTurnedOff() throws {
        var s = AppSettings()
        #expect(s.checkForUpdates)
        s.checkForUpdates = false
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s)).checkForUpdates == false)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).checkForUpdates)
    }
}

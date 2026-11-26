import Foundation
import Testing
@testable import DzhmilCore

@Suite struct ProcessRunnerTests {
    @Test func capturesStdout() async {
        let r = await ProcessRunner.run("/bin/echo", ["hi"])
        #expect(r.stdout == "hi\n")
        #expect(r.exitCode == 0)
        #expect(!r.timedOut)
    }

    @Test func timesOut() async {
        let started = Date()
        let r = await ProcessRunner.run("/bin/sleep", ["5"], timeout: .seconds(1))
        #expect(r.timedOut)
        #expect(Date().timeIntervalSince(started) < 2.5)
    }

    @Test func largeOutputDoesNotDeadlock() async {
        let r = await ProcessRunner.run("/bin/zsh", ["-c", "head -c 300000 /dev/zero | tr '\\0' a"])
        #expect(r.stdout.count == 300_000)
    }

    @Test func hugeOutputIsCappedWhileDraining() async {
        let r = await ProcessRunner.run("/bin/zsh", ["-c", "head -c 3000000 /dev/zero | tr '\\0' a"])
        #expect(r.exitCode == 0)
        #expect(!r.timedOut)
        #expect(r.stdout.count <= ProcessRunner.outputCap + 65_536)
        #expect(r.stdout.count >= ProcessRunner.outputCap)
    }

    @Test func capturesStderrAndExitCode() async {
        let r = await ProcessRunner.run("/bin/zsh", ["-c", "echo oops >&2; exit 3"])
        #expect(r.stderr == "oops\n")
        #expect(r.exitCode == 3)
    }

    @Test func missingExecutable() async {
        let r = await ProcessRunner.run("/nope/nothing", [])
        #expect(r.exitCode != 0)
    }
}

@Suite struct AppResolverTests {
    let apps: [AppCandidate] = [
        "Safari", "Google Chrome", "Telegram", "Visual Studio Code", "Terminal", "Finder", "System Settings", "Notes",
    ].map { AppCandidate(name: $0, bundleID: nil, url: nil, isRunning: false) }

    func resolve(_ q: String) -> String? { AppResolver.resolve(q, among: apps)?.name }

    @Test func exactAndCase() {
        #expect(resolve("safari") == "Safari")
        #expect(resolve("Notes.app") == "Notes")
    }

    @Test func englishAliases() {
        #expect(resolve("chrome") == "Google Chrome")
        #expect(resolve("vs code") == "Visual Studio Code")
        #expect(resolve("vscode") == "Visual Studio Code")
        #expect(resolve("code") == "Visual Studio Code")
        #expect(resolve("settings") == "System Settings")
        #expect(resolve("system preferences") == "System Settings")
    }

    @Test func prefixMatch() {
        #expect(resolve("tele") == "Telegram")
    }

    @Test func unknownIsNil() {
        #expect(resolve("photoshop") == nil)
        #expect(resolve("") == nil)
    }

    @Test func runningWinsTies() {
        let pair = [AppCandidate(name: "Notion", bundleID: nil, url: nil, isRunning: false),
                    AppCandidate(name: "Notion Calendar", bundleID: nil, url: nil, isRunning: true)]
        #expect(AppResolver.resolve("noti", among: pair)?.name == "Notion Calendar")
    }
}

@Suite struct SystemMetricsTests {
    @Test func saneValues() async {
        let s = await SystemMetrics.current()
        #expect(s.memoryTotalGB > 1)
        #expect(s.diskFreeGB > 0)
        #expect(s.uptime > 0)
        #expect((0...100).contains(s.cpuLoadPercent))
        #expect(s.summary.contains("Memory"))
        #expect(s.summary.contains("Disk"))
    }
}

@Suite struct TimerStoreTests {
    @Test func firesOnceWhenDue() async {
        let store = TimerStore()
        let t0 = Date()
        await store.add(label: "kettle", fireAt: t0.addingTimeInterval(300))
        #expect(await store.due(now: t0).isEmpty)
        #expect(await store.due(now: t0.addingTimeInterval(360)) == ["kettle"])
        #expect(await store.due(now: t0.addingTimeInterval(400)).isEmpty)
    }

    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dzhmil-\(UUID().uuidString)/timers.json")
    }

    @Test func timersSurviveARestart() async {
        let file = tempFile()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let first = TimerStore(file: file)
        await first.add(label: "kettle", fireAt: t0.addingTimeInterval(300))
        await first.add(label: "call", fireAt: t0.addingTimeInterval(900))
        let second = TimerStore(file: file)
        #expect(await second.due(now: t0.addingTimeInterval(400)) == ["kettle"])
        let third = TimerStore(file: file)
        #expect(await third.due(now: t0.addingTimeInterval(400)).isEmpty)
        #expect(await third.due(now: t0.addingTimeInterval(1000)) == ["call"])
    }

    @Test func corruptTimerFileStartsEmpty() async throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: file)
        let store = TimerStore(file: file)
        #expect(await store.isEmpty)
    }
}

@Suite struct MacToolsTests {
    let tools = MacToolbox.all(timers: TimerStore())
    func tool(_ name: String) -> any Tool { tools.first { $0.name == name }! }

    @Test func exactToolSet() {
        #expect(Set(tools.map(\.name)) == ["get_system_status", "list_running_apps", "open_app", "open_url", "set_volume", "mute", "set_timer", "quit_app", "force_quit_app", "system_power", "run_applescript", "run_shell"])
        #expect(tools.count == 12)
    }

    @Test func risks() {
        for name in ["quit_app", "force_quit_app", "run_applescript", "run_shell"] {
            #expect(tool(name).risk(for: [:]) == .needsConfirmation)
        }
        #expect(tool("system_power").risk(for: ["action": "lock"]) == .safe)
        for action in ["sleep", "restart", "shutdown"] {
            #expect(tool("system_power").risk(for: ["action": .string(action)]) == .needsConfirmation)
        }
        for name in ["get_system_status", "list_running_apps", "open_app", "open_url", "set_volume", "mute", "set_timer"] {
            #expect(tool(name).risk(for: [:]) == .safe)
        }
    }

    @Test func openURLCarryingDataNeedsConfirmation() {
        let open = tool("open_url")
        #expect(open.risk(for: ["url": "https://evil.example/?d=secret"]) == .needsConfirmation)
        #expect(open.risk(for: ["url": "https://example.com/page#frag"]) == .needsConfirmation)
        #expect(open.risk(for: ["url": "https://evil.example/leak/secret-text"]) == .needsConfirmation)
        #expect(open.risk(for: ["url": "https://github.com/Bogdusik"]) == .needsConfirmation)
        #expect(open.risk(for: ["url": "https://user:pw@example.com"]) == .needsConfirmation)
        #expect(open.risk(for: ["url": "https://example.com:8443"]) == .needsConfirmation)
        #expect(open.risk(for: ["url": "youtube.com"]) == .safe)
        #expect(open.risk(for: ["url": "https://www.youtube.com/"]) == .safe)
        #expect(open.risk(for: ["url": "how to cook pasta"]) == .safe)
        let c = open.confirmation(for: ["url": "https://evil.example/?d=secret"], language: .english)
        #expect(c.question == "Open this link?")
        #expect(c.detail == "https://evil.example/?d=secret")
    }

    @Test func confirmationTexts() {
        #expect(tool("quit_app").confirmation(for: ["app": "Safari"], language: .english).question == "Quit Safari?")
        let shell = tool("run_shell").confirmation(for: ["command": "ls"], language: .english)
        #expect(shell.question == "Run this command in Terminal?")
        #expect(shell.detail == "ls")
        #expect(tool("run_applescript").confirmation(for: ["script": "beep"], language: .english).detail == "beep")
    }

    @Test func schemasRequireAllProperties() {
        for t in tools {
            let props = t.inputSchema["properties"]
            let required = t.inputSchema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
            if case .object(let p)? = props {
                #expect(Set(p.keys) == Set(required), "\(t.name)")
            }
        }
    }

    @Test func timerRange() async {
        await #expect(throws: ToolError.self) { try await tool("set_timer").run(["minutes": 0, "label": "x"]) }
        await #expect(throws: ToolError.self) { try await tool("set_timer").run(["minutes": 2000, "label": "x"]) }
        let ok = try? await tool("set_timer").run(["minutes": 5, "label": "kettle"])
        #expect(ok != nil)
    }

    @Test func listsRunningApps() async throws {
        #expect(try await tool("list_running_apps").run([:]).contains("Finder"))
    }

    @Test func lockSaysWhatReallyHappened() async throws {
        #expect(try await SystemPowerTool(lockScreen: { true }).run(["action": "lock"]) == "Screen locked.")
        let fallback = try await SystemPowerTool(lockScreen: { false }).run(["action": "lock"])
        #expect(fallback.contains("Turned the display off"))
        #expect(fallback.contains("password"))
    }

    @Test func hugeNumbersDoNotCrashTools() async {
        await #expect(throws: ToolError.self) { try await tool("set_timer").run(["minutes": .number(1e20), "label": "x"]) }
        await #expect(throws: ToolError.self) { try await tool("set_volume").run(["percent": .number(-1e300)]) }
    }

    @Test func shellRunsAndReportsExitCode() async throws {
        let out = try await tool("run_shell").run(["command": "echo hello"])
        #expect(out.contains("hello"))
        #expect(out.contains("0"))
    }
}

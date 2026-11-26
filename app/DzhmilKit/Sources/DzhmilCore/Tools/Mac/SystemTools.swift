import Foundation

struct SystemStatusTool: SafeTool {
    let name = "get_system_status"
    let description = "Mac status: battery, CPU load, memory, free disk space and uptime."
    let inputSchema = Schema.object([:])

    func run(_ input: JSONValue) async throws -> String {
        await SystemMetrics.current().summary
    }
}

struct SetVolumeTool: SafeTool {
    let name = "set_volume"
    let description = "Set the output volume in percent, from 0 to 100."
    let inputSchema = Schema.object(["percent": Schema.integer("Volume from 0 to 100")])

    func run(_ input: JSONValue) async throws -> String {
        let p = min(100, max(0, try input.requiredInt("percent")))
        _ = try await AppleScript.run("set volume output volume \(p) without output muted")
        return "Volume \(p)%."
    }
}

struct MuteTool: SafeTool {
    let name = "mute"
    let description = "Mute (true) or unmute (false) the sound."
    let inputSchema = Schema.object(["muted": ["type": "boolean", "description": "true to mute"]])

    func run(_ input: JSONValue) async throws -> String {
        guard case .bool(let muted)? = input["muted"] else { throw ToolError.message("Missing parameter muted.") }
        _ = try await AppleScript.run("set volume output muted \(muted)")
        return muted ? "Sound muted." : "Sound unmuted."
    }
}

struct SetTimerTool: SafeTool {
    let timers: TimerStore
    let name = "set_timer"
    let description = "Set a reminder: Dzhmil reminds the user after the given number of minutes (1 to 1440)."
    let inputSchema = Schema.object([
        "minutes": Schema.integer("In how many minutes to remind, 1 to 1440"),
        "label": Schema.string("What to remind about"),
    ])

    func run(_ input: JSONValue) async throws -> String {
        let minutes = try input.requiredInt("minutes")
        guard (1...1440).contains(minutes) else { throw ToolError.message("A timer can be set for 1 to 1440 minutes.") }
        let label = try input.requiredString("label")
        await timers.add(label: label, fireAt: Date().addingTimeInterval(TimeInterval(minutes * 60)))
        return "Timer set for \(minutes) min: \(label)."
    }
}

struct SystemPowerTool: Tool {
    var lockScreen: @Sendable () async -> Bool = ScreenLock.lock
    let name = "system_power"
    let description = "Lock the screen (lock), sleep (sleep), restart (restart) or shut down (shutdown) the Mac."
    let inputSchema = Schema.object(["action": ["type": "string", "enum": ["lock", "sleep", "restart", "shutdown"], "description": "What to do"]])

    func risk(for input: JSONValue) -> ToolRisk {
        input["action"]?.stringValue == "lock" ? .safe : .needsConfirmation
    }

    func confirmation(for input: JSONValue, language: Language) -> ConfirmationRequest {
        let warning = language.pick("Unsaved work may be lost.", "Несохранённые данные могут пропасть.")
        return switch input["action"]?.stringValue {
        case "sleep": ConfirmationRequest(question: language.pick("Put the Mac to sleep?", "Усыпить Mac?"), detail: nil)
        case "restart": ConfirmationRequest(question: language.pick("Restart the Mac?", "Перезагрузить Mac?"), detail: warning)
        case "shutdown": ConfirmationRequest(question: language.pick("Shut down the Mac?", "Выключить Mac?"), detail: warning)
        default: ConfirmationRequest(question: language.pick("Lock the screen?", "Заблокировать экран?"), detail: nil)
        }
    }

    func run(_ input: JSONValue) async throws -> String {
        switch try input.requiredString("action") {
        case "lock":
            if await lockScreen() { return "Screen locked." }
            return "Turned the display off. The Mac locks only if a password is required after the display sleeps."
        case "sleep":
            _ = try await AppleScript.run("tell application \"System Events\" to sleep")
            return "Putting the Mac to sleep."
        case "restart":
            _ = try await AppleScript.run("tell application \"System Events\" to restart")
            return "Restarting the Mac."
        case "shutdown":
            _ = try await AppleScript.run("tell application \"System Events\" to shut down")
            return "Shutting down the Mac."
        default:
            throw ToolError.message("Unknown action.")
        }
    }
}

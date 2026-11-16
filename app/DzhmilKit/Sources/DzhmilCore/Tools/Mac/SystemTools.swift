import Foundation

struct SystemStatusTool: SafeTool {
    let name = "get_system_status"
    let description = "Состояние Mac: заряд батареи, загрузка процессора, память, свободное место на диске, время без перезагрузки."
    let inputSchema = Schema.object([:])

    func run(_ input: JSONValue) async throws -> String {
        await SystemMetrics.current().summary
    }
}

struct SetVolumeTool: SafeTool {
    let name = "set_volume"
    let description = "Установить громкость звука в процентах от 0 до 100."
    let inputSchema = Schema.object(["percent": Schema.integer("Громкость от 0 до 100")])

    func run(_ input: JSONValue) async throws -> String {
        let p = min(100, max(0, try input.requiredInt("percent")))
        _ = try await AppleScript.run("set volume output volume \(p) without output muted")
        return "Громкость \(p)%."
    }
}

struct MuteTool: SafeTool {
    let name = "mute"
    let description = "Выключить (true) или включить обратно (false) звук."
    let inputSchema = Schema.object(["muted": ["type": "boolean", "description": "true — выключить звук"]])

    func run(_ input: JSONValue) async throws -> String {
        guard case .bool(let muted)? = input["muted"] else { throw ToolError.message("Не хватает параметра muted.") }
        _ = try await AppleScript.run("set volume output muted \(muted)")
        return muted ? "Звук выключен." : "Звук включён."
    }
}

struct SetTimerTool: SafeTool {
    let timers: TimerStore
    let name = "set_timer"
    let description = "Поставить напоминание: Джміль сам напомнит через указанное число минут (от 1 до 1440)."
    let inputSchema = Schema.object([
        "minutes": Schema.integer("Через сколько минут напомнить, от 1 до 1440"),
        "label": Schema.string("О чём напомнить"),
    ])

    func run(_ input: JSONValue) async throws -> String {
        let minutes = try input.requiredInt("minutes")
        guard (1...1440).contains(minutes) else { throw ToolError.message("Таймер можно поставить от 1 до 1440 минут.") }
        let label = try input.requiredString("label")
        await timers.add(label: label, fireAt: Date().addingTimeInterval(TimeInterval(minutes * 60)))
        return "Поставил таймер на \(minutes) мин: \(label)."
    }
}

struct SystemPowerTool: Tool {
    let name = "system_power"
    let description = "Заблокировать экран (lock), усыпить (sleep), перезагрузить (restart) или выключить (shutdown) Mac."
    let inputSchema = Schema.object(["action": ["type": "string", "enum": ["lock", "sleep", "restart", "shutdown"], "description": "Что сделать"]])

    func risk(for input: JSONValue) -> ToolRisk {
        input["action"]?.stringValue == "lock" ? .safe : .needsConfirmation
    }

    func confirmation(for input: JSONValue) -> ConfirmationRequest {
        switch input["action"]?.stringValue {
        case "sleep": ConfirmationRequest(question: "Усыпить Mac?", detail: nil)
        case "restart": ConfirmationRequest(question: "Перезагрузить Mac?", detail: "Несохранённые данные могут пропасть.")
        case "shutdown": ConfirmationRequest(question: "Выключить Mac?", detail: "Несохранённые данные могут пропасть.")
        default: ConfirmationRequest(question: "Заблокировать экран?", detail: nil)
        }
    }

    func run(_ input: JSONValue) async throws -> String {
        switch try input.requiredString("action") {
        case "lock":
            _ = await ProcessRunner.run("/usr/bin/pmset", ["displaysleepnow"])
            return "Экран заблокирован."
        case "sleep":
            _ = try await AppleScript.run("tell application \"System Events\" to sleep")
            return "Усыпляю Mac."
        case "restart":
            _ = try await AppleScript.run("tell application \"System Events\" to restart")
            return "Перезагружаю Mac."
        case "shutdown":
            _ = try await AppleScript.run("tell application \"System Events\" to shut down")
            return "Выключаю Mac."
        default:
            throw ToolError.message("Неизвестное действие.")
        }
    }
}

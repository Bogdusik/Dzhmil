import Foundation

struct AppleScriptTool: Tool {
    let name = "run_applescript"
    let description = "Выполнить AppleScript для всего, что не покрывают другие инструменты: управление приложениями, окнами, Finder, Музыкой и т. п."
    let inputSchema = Schema.object(["script": Schema.string("Текст AppleScript")])

    func risk(for input: JSONValue) -> ToolRisk { .needsConfirmation }

    func confirmation(for input: JSONValue) -> ConfirmationRequest {
        ConfirmationRequest(question: "Выполнить AppleScript?", detail: input["script"]?.stringValue)
    }

    func run(_ input: JSONValue) async throws -> String {
        let out = try await AppleScript.run(try input.requiredString("script"))
        return out.isEmpty ? "Готово." : out
    }
}

struct ShellTool: Tool {
    let name = "run_shell"
    let description = "Выполнить команду в zsh от имени пользователя. Таймаут 30 секунд, длинный вывод обрезается."
    let inputSchema = Schema.object(["command": Schema.string("Команда для zsh")])

    func risk(for input: JSONValue) -> ToolRisk { .needsConfirmation }

    func confirmation(for input: JSONValue) -> ConfirmationRequest {
        ConfirmationRequest(question: "Выполнить команду в терминале?", detail: input["command"]?.stringValue)
    }

    func run(_ input: JSONValue) async throws -> String {
        let command = try input.requiredString("command")
        let r = await ProcessRunner.run("/bin/zsh", ["-lc", command])
        if r.timedOut { throw ToolError.message("Команда не завершилась за 30 секунд и была остановлена.\n" + r.stdout + r.stderr) }
        var parts = ["Код выхода: \(r.exitCode)"]
        if !r.stdout.isEmpty { parts.append(r.stdout) }
        if !r.stderr.isEmpty { parts.append("stderr:\n" + r.stderr) }
        return parts.joined(separator: "\n")
    }
}

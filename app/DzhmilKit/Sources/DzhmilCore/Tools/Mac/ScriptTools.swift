import Foundation

struct AppleScriptTool: Tool {
    let name = "run_applescript"
    let description = "Run AppleScript for anything the other tools don't cover: controlling apps, windows, Finder, Music and so on."
    let inputSchema = Schema.object(["script": Schema.string("AppleScript source")])

    func risk(for input: JSONValue) -> ToolRisk { .needsConfirmation }

    func confirmation(for input: JSONValue) -> ConfirmationRequest {
        ConfirmationRequest(question: "Run this AppleScript?", detail: input["script"]?.stringValue)
    }

    func run(_ input: JSONValue) async throws -> String {
        let out = try await AppleScript.run(try input.requiredString("script"))
        return out.isEmpty ? "Done." : out
    }
}

struct ShellTool: Tool {
    let name = "run_shell"
    let description = "Run a command in zsh as the user. 30-second timeout; long output is cut."
    let inputSchema = Schema.object(["command": Schema.string("Command for zsh")])

    func risk(for input: JSONValue) -> ToolRisk { .needsConfirmation }

    func confirmation(for input: JSONValue) -> ConfirmationRequest {
        ConfirmationRequest(question: "Run this command in Terminal?", detail: input["command"]?.stringValue)
    }

    func run(_ input: JSONValue) async throws -> String {
        let command = try input.requiredString("command")
        let r = await ProcessRunner.run("/bin/zsh", ["-lc", command])
        if r.timedOut { throw ToolError.message("The command didn't finish in 30 seconds and was stopped.\n" + r.stdout + r.stderr) }
        var parts = ["Exit code: \(r.exitCode)"]
        if !r.stdout.isEmpty { parts.append(r.stdout) }
        if !r.stderr.isEmpty { parts.append("stderr:\n" + r.stderr) }
        return parts.joined(separator: "\n")
    }
}

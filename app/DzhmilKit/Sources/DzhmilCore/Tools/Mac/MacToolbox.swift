import Foundation

public enum MacToolbox {
    public static func all(timers: TimerStore, screen: (any ScreenCapturer)? = nil,
                           beforeCapture: @escaping @Sendable () async -> Bool = { true },
                           pointer: (@Sendable (PointRequest) async -> Bool)? = nil,
                           now: @escaping @Sendable () -> Date = { Date() }) -> [any Tool] {
        var tools: [any Tool] = [
            SystemStatusTool(),
            ListRunningAppsTool(),
            OpenAppTool(),
            OpenURLTool(),
            SetVolumeTool(),
            MuteTool(),
            SetTimerTool(timers: timers),
            QuitAppTool(force: false),
            QuitAppTool(force: true),
            SystemPowerTool(),
            AppleScriptTool(),
            ShellTool(),
        ]
        if let screen {
            let memory = ScreenshotMemory()
            tools.append(LookAtScreenTool(capturer: screen, beforeCapture: beforeCapture, memory: memory, now: now))
            if let pointer { tools.append(PointAtTool(memory: memory, pointer: pointer, now: now)) }
        }
        return tools
    }
}

enum Schema {
    static func object(_ props: [String: JSONValue]) -> JSONValue {
        ["type": "object", "properties": .object(props), "required": .array(props.keys.sorted().map { .string($0) })]
    }

    static func string(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    static func integer(_ description: String) -> JSONValue {
        ["type": "integer", "description": .string(description)]
    }
}

extension JSONValue {
    func requiredString(_ key: String) throws -> String {
        guard let s = self[key]?.stringValue, !s.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ToolError.message("Не хватает параметра \(key).")
        }
        return s
    }

    func requiredInt(_ key: String) throws -> Int {
        guard let n = self[key]?.intValue else { throw ToolError.message("Не хватает параметра \(key).") }
        return n
    }
}

protocol SafeTool: Tool {}
extension SafeTool {
    func risk(for input: JSONValue) -> ToolRisk { .safe }
    func confirmation(for input: JSONValue) -> ConfirmationRequest { ConfirmationRequest(question: "", detail: nil) }
}

enum AppleScript {
    static func run(_ script: String, timeout: Duration = .seconds(30)) async throws -> String {
        let r = await ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: timeout)
        if r.timedOut { throw ToolError.message("Скрипт не завершился за 30 секунд.") }
        if r.exitCode != 0 {
            throw ToolError.message(r.stderr.isEmpty ? "AppleScript завершился с кодом \(r.exitCode)." : r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

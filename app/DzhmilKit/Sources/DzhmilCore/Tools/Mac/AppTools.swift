import AppKit
import Foundation

enum InstalledApps {
    static let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities",
                          NSHomeDirectory() + "/Applications"]

    static func running() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }

    static func candidates(runningOnly: Bool) -> [AppCandidate] {
        var seen = Set<String>()
        var out: [AppCandidate] = []
        for app in running() {
            guard let name = app.localizedName, seen.insert(name).inserted else { continue }
            out.append(AppCandidate(name: name, bundleID: app.bundleIdentifier, url: app.bundleURL, isRunning: true))
        }
        guard !runningOnly else { return out }
        for folder in folders {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            for item in items where item.hasSuffix(".app") {
                let name = String(item.dropLast(4))
                guard seen.insert(name).inserted else { continue }
                out.append(AppCandidate(name: name, bundleID: nil, url: URL(fileURLWithPath: folder).appendingPathComponent(item), isRunning: false))
            }
        }
        return out
    }

    static func runningNames() -> String {
        running().compactMap(\.localizedName).joined(separator: ", ")
    }

    static func notFound(_ query: String) -> ToolError {
        .message("Не нашёл приложение «\(query)». Запущены: \(runningNames()).")
    }
}

struct ListRunningAppsTool: SafeTool {
    let name = "list_running_apps"
    let description = "Список запущенных приложений с окнами."
    let inputSchema = Schema.object([:])

    func run(_ input: JSONValue) async throws -> String {
        "Запущены: " + InstalledApps.runningNames()
    }
}

struct OpenAppTool: SafeTool {
    let name = "open_app"
    let description = "Открыть или переключиться на приложение по названию, например Safari или Telegram."
    let inputSchema = Schema.object(["app": Schema.string("Название приложения")])

    func run(_ input: JSONValue) async throws -> String {
        let query = try input.requiredString("app")
        guard let app = AppResolver.resolve(query, among: InstalledApps.candidates(runningOnly: false)) else {
            throw InstalledApps.notFound(query)
        }
        if app.isRunning, let running = InstalledApps.running().first(where: { $0.localizedName == app.name }) {
            running.activate()
            return "Переключился на \(app.name)."
        }
        guard let url = app.url else { throw InstalledApps.notFound(query) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return "Открыл \(app.name)."
    }
}

struct QuitAppTool: Tool {
    let force: Bool
    var name: String { force ? "force_quit_app" : "quit_app" }
    var description: String {
        force ? "Принудительно завершить зависшее приложение. Несохранённые данные пропадут."
              : "Закрыть приложение. Оно само спросит про несохранённые документы."
    }
    let inputSchema = Schema.object(["app": Schema.string("Название приложения")])

    func risk(for input: JSONValue) -> ToolRisk { .needsConfirmation }

    func confirmation(for input: JSONValue) -> ConfirmationRequest {
        let query = input["app"]?.stringValue ?? "приложение"
        let shown = AppResolver.resolve(query, among: InstalledApps.candidates(runningOnly: true))?.name ?? query
        return ConfirmationRequest(question: force ? "Принудительно завершить \(shown)?" : "Закрыть \(shown)?",
                                   detail: force ? "Несохранённые данные пропадут." : nil)
    }

    func run(_ input: JSONValue) async throws -> String {
        let query = try input.requiredString("app")
        guard let app = AppResolver.resolve(query, among: InstalledApps.candidates(runningOnly: true)),
              let running = InstalledApps.running().first(where: { $0.localizedName == app.name }) else {
            throw ToolError.message("«\(query)» не запущено. Запущены: \(InstalledApps.runningNames()).")
        }
        let ok = force ? running.forceTerminate() : running.terminate()
        guard ok else { throw ToolError.message("\(app.name) не закрылось.") }
        return force ? "Завершил \(app.name)." : "Попросил \(app.name) закрыться."
    }
}

struct OpenURLTool: Tool {
    let name = "open_url"
    let description = "Открыть ссылку в браузере. Если передан не адрес, а текст, открывается поиск Google."
    let inputSchema = Schema.object(["url": Schema.string("Адрес или поисковый запрос")])

    static func directURL(_ raw: String) -> URL? {
        if let u = URL(string: raw), let scheme = u.scheme, ["http", "https"].contains(scheme.lowercased()) { return u }
        if !raw.contains(" "), raw.contains("."), let u = URL(string: "https://" + raw) { return u }
        return nil
    }

    func risk(for input: JSONValue) -> ToolRisk {
        let raw = (input["url"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        guard let url = Self.directURL(raw) else { return .safe }
        let hasPayload = !(url.query ?? "").isEmpty || !(url.fragment ?? "").isEmpty
        return hasPayload ? .needsConfirmation : .safe
    }

    func confirmation(for input: JSONValue) -> ConfirmationRequest {
        ConfirmationRequest(question: "Открыть ссылку?", detail: input["url"]?.stringValue)
    }

    func run(_ input: JSONValue) async throws -> String {
        let raw = try input.requiredString("url").trimmingCharacters(in: .whitespaces)
        let url: URL?
        if let u = Self.directURL(raw) {
            url = u
        } else {
            var c = URLComponents(string: "https://www.google.com/search")
            c?.queryItems = [URLQueryItem(name: "q", value: raw)]
            url = c?.url
        }
        guard let url, NSWorkspace.shared.open(url) else { throw ToolError.message("Не получилось открыть «\(raw)».") }
        return "Открыл \(url.absoluteString)."
    }
}

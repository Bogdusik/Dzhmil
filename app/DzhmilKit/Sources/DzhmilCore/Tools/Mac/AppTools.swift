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
        .message("Couldn't find an app called “\(query)”. Running: \(runningNames()).")
    }
}

struct ListRunningAppsTool: SafeTool {
    let name = "list_running_apps"
    let description = "List the running apps that have windows."
    let inputSchema = Schema.object([:])

    func run(_ input: JSONValue) async throws -> String {
        "Running: " + InstalledApps.runningNames()
    }
}

struct OpenAppTool: SafeTool {
    let name = "open_app"
    let description = "Open or switch to an app by name, for example Safari or Telegram."
    let inputSchema = Schema.object(["app": Schema.string("App name")])

    func run(_ input: JSONValue) async throws -> String {
        let query = try input.requiredString("app")
        guard let app = AppResolver.resolve(query, among: InstalledApps.candidates(runningOnly: false)) else {
            throw InstalledApps.notFound(query)
        }
        if app.isRunning, let running = InstalledApps.running().first(where: { $0.localizedName == app.name }) {
            running.activate()
            return "Switched to \(app.name)."
        }
        guard let url = app.url else { throw InstalledApps.notFound(query) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return "Opened \(app.name)."
    }
}

struct QuitAppTool: Tool {
    let force: Bool
    var name: String { force ? "force_quit_app" : "quit_app" }
    var description: String {
        force ? "Force quit a frozen app. Unsaved work will be lost."
              : "Quit an app. It asks about unsaved documents itself."
    }
    let inputSchema = Schema.object(["app": Schema.string("App name")])

    func risk(for input: JSONValue) -> ToolRisk { .needsConfirmation }

    func confirmation(for input: JSONValue) -> ConfirmationRequest {
        let query = input["app"]?.stringValue ?? "the app"
        let shown = AppResolver.resolve(query, among: InstalledApps.candidates(runningOnly: true))?.name ?? query
        return ConfirmationRequest(question: force ? "Force quit \(shown)?" : "Quit \(shown)?",
                                   detail: force ? "Unsaved work will be lost." : nil)
    }

    func run(_ input: JSONValue) async throws -> String {
        let query = try input.requiredString("app")
        guard let app = AppResolver.resolve(query, among: InstalledApps.candidates(runningOnly: true)),
              let running = InstalledApps.running().first(where: { $0.localizedName == app.name }) else {
            throw ToolError.message("“\(query)” isn't running. Running: \(InstalledApps.runningNames()).")
        }
        let ok = force ? running.forceTerminate() : running.terminate()
        guard ok else { throw ToolError.message("\(app.name) didn't quit.") }
        return force ? "Force quit \(app.name)." : "Asked \(app.name) to quit."
    }
}

struct OpenURLTool: Tool {
    let name = "open_url"
    let description = "Open a link in the browser. If the input is text rather than an address, a Google search opens."
    let inputSchema = Schema.object(["url": Schema.string("Address or search query")])
    let asksAfterUntrustedContent = true

    static func directURL(_ raw: String) -> URL? {
        if let u = URL(string: raw), let scheme = u.scheme, ["http", "https"].contains(scheme.lowercased()) { return u }
        if !raw.contains(" "), raw.contains("."), let u = URL(string: "https://" + raw) { return u }
        return nil
    }

    func risk(for input: JSONValue) -> ToolRisk {
        let raw = (input["url"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        guard let url = Self.directURL(raw) else { return .safe }
        return Self.isBareSite(url) ? .safe : .needsConfirmation
    }

    static func isBareSite(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return ["", "/"].contains(parts.percentEncodedPath)
            && parts.query == nil && parts.fragment == nil
            && parts.user == nil && parts.password == nil && parts.port == nil
    }

    func confirmation(for input: JSONValue) -> ConfirmationRequest {
        ConfirmationRequest(question: "Open this link?", detail: input["url"]?.stringValue)
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
        guard let url, NSWorkspace.shared.open(url) else { throw ToolError.message("Couldn't open “\(raw)”.") }
        return "Opened \(url.absoluteString)."
    }
}

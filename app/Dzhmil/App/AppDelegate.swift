import AppKit
import DzhmilCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let companion = Companion()
    private var menuBar: MenuBarController?
    private var onboarding: Onboarding?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if handleDebugArguments() { return }
        #endif
        menuBar = MenuBarController(companion: companion)
        companion.start()
        let onboarding = Onboarding(companion: companion)
        onboarding.startIfNeeded()
        self.onboarding = onboarding
        if CommandLine.arguments.contains("--request-screen-access") {
            MenuBarController.requestScreenAccess()
        }
        #if DEBUG
        if CommandLine.arguments.contains("--proactive-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [companion] in companion.proactive.fire(.dailyGreeting) }
        }
        #endif
    }

    #if DEBUG
    private func argument(after flag: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    private func handleDebugArguments() -> Bool {
        if let dir = argument(after: "--render-states") {
            StateGallery.renderAll(to: URL(fileURLWithPath: dir))
            NSApp.terminate(nil)
            return true
        }
        if let path = argument(after: "--transcribe-test") {
            Task {
                await DebugTools.transcribeTest(path: path)
                NSApp.terminate(nil)
            }
            return true
        }
        if let seconds = argument(after: "--idle-seconds") {
            companion.director.idleOverride = TimeInterval(seconds)
        }
        return false
    }
    #endif
}

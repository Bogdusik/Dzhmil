import Foundation
import KeyboardShortcuts
import DzhmilCore

@MainActor
final class Onboarding {
    static let greeting = "Hi! I'm Dzhmil. To think, I need an API key from the Claude Console. Paste it here."

    private unowned let companion: Companion

    init(companion: Companion) {
        self.companion = companion
    }

    func startIfNeeded() {
        guard companion.keychain.read() == nil else { return }
        companion.onboardingSubmit = { [weak self] key in self?.submit(key) }
        Task {
            try? await Task.sleep(for: .seconds(3))
            companion.showOnboarding(Self.greeting)
        }
    }

    private func submit(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            companion.showOnboarding(Self.greeting)
            return
        }
        do {
            try companion.keychain.save(key)
        } catch {
            companion.showOnboarding("Couldn't save the key in the Keychain. Please try again.")
            return
        }
        companion.say("Checking the key…")
        Task {
            switch await companion.checkKey() {
            case nil:
                let hotkey = KeyboardShortcuts.getShortcut(for: .pushToTalk)?.description ?? "⌥Space"
                companion.say("All set! Hold \(hotkey) and talk, and I'll answer when you let go. Double-click me to type instead.")
            case let error? where error.meansBadKey:
                try? companion.keychain.delete()
                companion.showOnboarding(error.userMessage + " Please try again.")
            case let error?:
                companion.say(error.userMessage + " I saved the key and will check it later.")
            }
        }
    }
}

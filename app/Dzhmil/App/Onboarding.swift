import Foundation
import KeyboardShortcuts
import DzhmilCore

@MainActor
final class Onboarding {
    static func greeting(_ language: Language) -> String {
        language.pick("Hi! I'm Dzhmil. To think, I need an API key from Claude, ChatGPT, Gemini or OpenRouter. Paste it here.",
                      "Привет! Я Джмиль. Чтобы думать, мне нужен API-ключ от Claude, ChatGPT, Gemini или OpenRouter. Вставь его сюда.")
    }

    private unowned let companion: Companion

    init(companion: Companion) {
        self.companion = companion
    }

    func startIfNeeded() {
        guard companion.settings.provider.needsKey else { return }
        let stored = companion.keychain.lookup()
        if case .found = stored { return }
        companion.onboardingSubmit = { [weak self] key in self?.submit(key) }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if stored == .blocked {
                companion.say(ChatError.keyBlocked.userMessage(in: companion.language))
            } else {
                companion.showOnboarding(Self.greeting(companion.language))
            }
        }
    }

    private func submit(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = companion.language
        guard !key.isEmpty else {
            companion.showOnboarding(Self.greeting(language))
            return
        }
        if let provider = Provider.detect(key: key), provider != companion.settings.provider {
            companion.settings.provider = provider
        }
        do {
            try companion.keychain.save(key)
        } catch {
            companion.showOnboarding(language.pick("Couldn't save the key in the Keychain. Please try again.", "Не получилось сохранить ключ в Связке ключей. Попробуй ещё раз."))
            return
        }
        companion.say(language.pick("Checking the key…", "Проверяю ключ…"))
        Task {
            switch await companion.checkKey() {
            case nil:
                let hotkey = KeyboardShortcuts.getShortcut(for: .pushToTalk)?.description ?? "⌥Space"
                companion.say(language.pick("All set! Hold \(hotkey) and talk, and I'll answer when you let go. Double-click me to type instead.",
                                            "Готово! Зажми \(hotkey) и говори, а я отвечу, когда отпустишь. Или дважды кликни по мне, чтобы написать."))
            case .keyBlocked?:
                companion.say(ChatError.keyBlocked.userMessage(in: language))
            case let error? where error.meansBadKey:
                if error.meansForgetKey { try? companion.keychain.delete() }
                companion.showOnboarding(error.userMessage(in: language) + language.pick(" Please try again.", " Попробуй ещё раз."))
            case let error?:
                companion.say(error.userMessage(in: language) + language.pick(" I saved the key and will check it later.", " Ключ сохранён, проверю позже."))
            }
        }
    }
}

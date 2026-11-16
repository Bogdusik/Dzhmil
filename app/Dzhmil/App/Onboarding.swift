import Foundation
import KeyboardShortcuts
import DzhmilCore

@MainActor
final class Onboarding {
    static let greeting = "Привет! Я Джміль. Чтобы думать, мне нужен ключ API из Claude Console. Вставь его сюда."

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

    private func submit(_ key: String) {
        do {
            try companion.keychain.save(key)
        } catch {
            companion.showOnboarding("Не получилось сохранить ключ в Keychain. Попробуй ещё раз.")
            return
        }
        companion.say("Проверяю ключ…")
        Task {
            if let error = await companion.checkKey() {
                try? companion.keychain.delete()
                companion.showOnboarding(error + " Попробуй ещё раз.")
            } else {
                let hotkey = KeyboardShortcuts.getShortcut(for: .pushToTalk)?.description ?? "⌥Space"
                companion.say("Готово! Зажми \(hotkey) и говори. Отпустишь — я отвечу. А дважды кликнув по мне, можно написать.")
            }
        }
    }
}

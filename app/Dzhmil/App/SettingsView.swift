import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import DzhmilCore

@MainActor
@Observable
final class SettingsModel {
    @ObservationIgnored private let companion: Companion
    var settings: AppSettings { didSet { companion.settings = settings } }
    var keyDraft = ""
    var keyStatus = ""
    var checking = false
    var profile: String
    var profileStatus = ""
    var loginError = ""

    init(companion: Companion) {
        self.companion = companion
        settings = companion.settings
        profile = companion.profileStore.load()
        keyStatus = companion.keychain.read() == nil ? "Ключ не сохранён." : "Ключ сохранён в Keychain."
    }

    func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try companion.keychain.save(key)
            keyDraft = ""
            keyStatus = "Ключ сохранён в Keychain."
        } catch {
            keyStatus = "Не получилось сохранить ключ."
        }
    }

    func checkKey() {
        if !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty { saveKey() }
        checking = true
        keyStatus = "Проверяю…"
        Task {
            let error = await companion.checkKey()
            checking = false
            keyStatus = error ?? "Ключ работает."
        }
    }

    func saveProfile() {
        do {
            try companion.profileStore.save(profile)
            companion.profileChanged()
            profileStatus = "Сохранено."
        } catch {
            profileStatus = "Не получилось сохранить."
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = on
            loginError = ""
        } catch {
            loginError = "macOS не разрешил: \(error.localizedDescription)"
            settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel

    private let modelTitles = ["claude-opus-5-5": "Claude Opus 5.5 (умнее)", "claude-sonnet-5-5": "Claude Sonnet 5.5", "claude-haiku-5-5": "Claude Haiku 5.5 (дешевле)"]
    private let effortTitles = ["low": "Быстро", "medium": "Средне", "high": "Вдумчиво"]

    var body: some View {
        Form {
            Section("Мозг") {
                SecureField("Ключ API", text: $model.keyDraft, prompt: Text("sk-ant-…"))
                    .onSubmit { model.saveKey() }
                HStack {
                    Button("Сохранить") { model.saveKey() }
                    Button("Проверить") { model.checkKey() }.disabled(model.checking)
                    Spacer()
                    Text(model.keyStatus).foregroundStyle(.secondary).font(.callout)
                }
                Picker("Модель", selection: $model.settings.model) {
                    ForEach(AppSettings.models, id: \.self) { Text(modelTitles[$0] ?? $0).tag($0) }
                }
                Picker("Как думать", selection: $model.settings.effort) {
                    ForEach(AppSettings.efforts, id: \.self) { Text(effortTitles[$0] ?? $0).tag($0) }
                }
            }
            Section("Голос") {
                KeyboardShortcuts.Recorder("Говорить:", name: .pushToTalk)
                Toggle("Отвечать голосом", isOn: $model.settings.voiceEnabled)
                Slider(value: $model.settings.voiceVolume, in: 0...1) { Text("Громкость") }
                    .disabled(!model.settings.voiceEnabled)
            }
            Section("Характер") {
                Picker("Заговаривает первым", selection: $model.settings.chattiness) {
                    ForEach(Chattiness.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Звук винтов", isOn: $model.settings.propellerSound)
            }
            Section("Система") {
                Toggle("Запускать при входе", isOn: Binding(get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                if !model.loginError.isEmpty {
                    Text(model.loginError).foregroundStyle(.red).font(.callout)
                }
            }
            Section("О тебе") {
                TextEditor(text: $model.profile)
                    .font(.body)
                    .frame(minHeight: 90)
                HStack {
                    Button("Сохранить") { model.saveProfile() }
                    Text(model.profileStatus).foregroundStyle(.secondary).font(.callout)
                }
                Text("Джміль читает это перед каждым разговором. Файл лежит в ~/Library/Application Support/Dzhmil/profile.md.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(companion: Companion) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: SettingsModel(companion: companion))))
            w.title = "Настройки Джмиля"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

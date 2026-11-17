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
    var profile: String { didSet { if !reloading { profileDirty = true } } }
    @ObservationIgnored private var profileDirty = false
    @ObservationIgnored private var reloading = false
    @ObservationIgnored private var profileObserver: NSObjectProtocol?
    var profileStatus = ""
    var loginError = ""

    init(companion: Companion) {
        self.companion = companion
        settings = companion.settings
        profile = companion.profileStore.load()
        keyStatus = companion.keychain.read() == nil ? "No key saved." : "Key saved in the Keychain."
        profileObserver = NotificationCenter.default.addObserver(forName: ProfileStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadProfile() }
        }
    }

    func reloadProfile() {
        guard !profileDirty else { return }
        reloading = true
        profile = companion.profileStore.load()
        reloading = false
    }

    func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try companion.keychain.save(key)
            keyDraft = ""
            keyStatus = "Key saved in the Keychain."
        } catch {
            keyStatus = "Couldn't save the key."
        }
    }

    func checkKey() {
        if !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty { saveKey() }
        checking = true
        keyStatus = "Checking…"
        Task {
            let error = await companion.checkKey()
            checking = false
            keyStatus = error?.userMessage ?? "The key works."
        }
    }

    func saveProfile() {
        do {
            profileDirty = false
            try companion.profileStore.save(profile)
            companion.profileChanged()
            profileStatus = "Saved."
        } catch {
            profileStatus = "Couldn't save."
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = on
            loginError = ""
        } catch {
            loginError = "macOS didn't allow it: \(error.localizedDescription)"
            settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel

    private let modelTitles = ["claude-opus-5-5": "Claude Opus 5.5 (smartest)", "claude-sonnet-5-5": "Claude Sonnet 5.5", "claude-haiku-5-5": "Claude Haiku 5.5 (cheapest)"]
    private let effortTitles = ["low": "Quick", "medium": "Balanced", "high": "Thorough"]

    var body: some View {
        Form {
            Section("Brain") {
                SecureField("API key", text: $model.keyDraft, prompt: Text("sk-ant-…"))
                    .onSubmit { model.saveKey() }
                HStack {
                    Button("Save") { model.saveKey() }
                    Button("Check") { model.checkKey() }.disabled(model.checking)
                    Spacer()
                    Text(model.keyStatus).foregroundStyle(.secondary).font(.callout)
                }
                Picker("Model", selection: $model.settings.model) {
                    ForEach(AppSettings.models, id: \.self) { Text(modelTitles[$0] ?? $0).tag($0) }
                }
                Picker("Thinking", selection: $model.settings.effort) {
                    ForEach(AppSettings.efforts, id: \.self) { Text(effortTitles[$0] ?? $0).tag($0) }
                }
            }
            Section("Voice") {
                KeyboardShortcuts.Recorder("Talk:", name: .pushToTalk)
                Toggle("Speak replies", isOn: $model.settings.voiceEnabled)
                Slider(value: $model.settings.voiceVolume, in: 0...1) { Text("Volume") }
                    .disabled(!model.settings.voiceEnabled)
            }
            Section("Personality") {
                Picker("Speaks first", selection: $model.settings.chattiness) {
                    ForEach(Chattiness.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Propeller sound", isOn: $model.settings.propellerSound)
            }
            Section("System") {
                Toggle("Open at login", isOn: Binding(get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                if !model.loginError.isEmpty {
                    Text(model.loginError).foregroundStyle(.red).font(.callout)
                }
            }
            Section("About you") {
                TextEditor(text: $model.profile)
                    .font(.body)
                    .frame(minHeight: 90)
                HStack {
                    Button("Save") { model.saveProfile() }
                    Text(model.profileStatus).foregroundStyle(.secondary).font(.callout)
                }
                Text("Dzhmil reads this before every conversation. The file is ~/Library/Application Support/Dzhmil/profile.md.")
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
            w.title = "Dzhmil Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            ScreenPrivacy.apply(to: w)
            window = w
        }
        (window?.contentViewController as? NSHostingController<SettingsView>)?.rootView.model.reloadProfile()
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

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
    var modelChoices: [String] = []
    var provider: Provider {
        get { settings.provider }
        set {
            settings.provider = newValue
            keyDraft = ""
            refreshKeyStatus()
            loadModels()
        }
    }
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
        refreshKeyStatus()
        loadModels()
        profileObserver = NotificationCenter.default.addObserver(forName: ProfileStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadProfile() }
        }
    }

    func refreshKeyStatus() {
        guard settings.provider.needsKey else {
            keyStatus = ""
            return
        }
        keyStatus = companion.keychain.read() == nil ? "No key saved." : "Key saved in the Keychain."
    }

    func loadModels() {
        let provider = settings.provider
        modelChoices = provider.suggestedModels
        guard provider != .anthropic, !provider.needsKey || companion.keychain.read() != nil else { return }
        let key = companion.keychain.read()
        Task {
            guard let ids = try? await ModelCatalog.fetch(provider, key: key), !ids.isEmpty,
                  settings.provider == provider else { return }
            modelChoices = provider == .openai ? provider.suggestedModels + ids.filter { !provider.suggestedModels.contains($0) } : ids
        }
    }

    var version: String { companion.updates.current.description }

    func checkForUpdates() {
        if companion.director.isHidden { companion.setHidden(false) }
        companion.updates.checkNow()
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
            loadModels()
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
            keyStatus = error?.userMessage ?? "It works."
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

    private let modelTitles = ["claude-opus-5-5": "Claude Opus 5.5 (smartest)", "claude-sonnet-5-5": "Claude Sonnet 5.5", "claude-haiku-5-5": "Claude Haiku 5.5 (cheapest)",
                               "gpt-6.2-astra": "GPT-6.2 Astra (smartest)", "gpt-6.2-sol": "GPT-6.2 Sol", "gpt-6-luna": "GPT-6 Luna (cheapest)",
                               "openrouter/auto": "Auto (OpenRouter picks)"]
    private let effortTitles = ["low": "Quick", "medium": "Balanced", "high": "Thorough"]

    var body: some View {
        Form {
            Section("Look") {
                DroneView(state: .hover, bankDegrees: 0, look: model.settings.look)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                ColorRow(title: "Body", presets: DroneColorPreset.all, color: $model.settings.droneColor)
                ColorRow(title: "Arms", presets: DroneColorPreset.parts, color: $model.settings.armColor)
                ColorRow(title: "Propellers", presets: DroneColorPreset.parts, color: $model.settings.propellerColor)
            }
            Section("Language") {
                Picker("Dzhmil speaks", selection: $model.settings.language) {
                    ForEach(Language.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Talk to Dzhmil in this language and it replies in it. Menus and settings stay in English. For a more natural voice, download an enhanced voice in System Settings under Accessibility, then restart Dzhmil.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Brain") {
                Picker("Provider", selection: $model.provider) {
                    ForEach(Provider.allCases) { Text($0.title).tag($0) }
                }
                if model.provider.needsKey {
                    SecureField("API key", text: $model.keyDraft, prompt: Text(model.provider.keyPlaceholder))
                        .onSubmit { model.saveKey() }
                } else {
                    Text("Runs on this Mac, free and offline. Install Ollama, then pull a model that can use tools, for example `ollama pull qwen3`.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if model.provider.needsKey { Button("Save") { model.saveKey() } }
                    Button("Check") { model.checkKey() }.disabled(model.checking)
                    Link(model.provider.needsKey ? "Get a key" : "Get Ollama", destination: model.provider.keyPage)
                    Spacer()
                    Text(model.keyStatus).foregroundStyle(.secondary).font(.callout)
                }
                if model.provider == .anthropic {
                    Picker("Model", selection: $model.settings.model) {
                        ForEach(AppSettings.models, id: \.self) { Text(modelTitles[$0] ?? $0).tag($0) }
                    }
                } else {
                    HStack {
                        TextField("Model", text: $model.settings.model, prompt: Text(model.provider.defaultModel))
                        Menu("Choose") {
                            ForEach(model.modelChoices, id: \.self) { id in
                                Button(modelTitles[id] ?? id) { model.settings.model = id }
                            }
                        }
                        .fixedSize()
                    }
                }
                Picker("Thinking", selection: $model.settings.effort) {
                    ForEach(AppSettings.efforts, id: \.self) { Text(effortTitles[$0] ?? $0).tag($0) }
                }
                .disabled(!model.provider.sendsEffort)
                if model.provider != .anthropic {
                    Text("Dzhmil is tuned for Claude. Other models work, but may point less precisely or skip tools; pick one that supports tool calling and images.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                Toggle("Check for updates", isOn: $model.settings.checkForUpdates)
                LabeledContent("Version \(model.version)") {
                    Button("Check Now") { model.checkForUpdates() }
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
        .frame(width: 500, height: 700)
    }
}

private struct ColorRow: View {
    let title: String
    let presets: [DroneColorPreset]
    @Binding var color: UInt32

    private var custom: Binding<Color> {
        Binding {
            Color(hex: color)
        } set: { new in
            guard let c = NSColor(new).usingColorSpace(.sRGB) else { return }
            func channel(_ v: CGFloat) -> UInt32 { UInt32((min(1, max(0, v)) * 255).rounded()) }
            color = channel(c.redComponent) << 16 | channel(c.greenComponent) << 8 | channel(c.blueComponent)
        }
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 5) {
                ForEach(presets) { preset in
                    Swatch(preset: preset, selected: color == preset.hex) { color = preset.hex }
                }
                ColorPicker("Custom \(title.lowercased()) color", selection: custom, supportsOpacity: false)
                    .labelsHidden()
                    .help("Custom color")
            }
        }
    }
}

private struct Swatch: View {
    let preset: DroneColorPreset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: preset.hex))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                .padding(3)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.8 : 0), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(preset.name.capitalized)
        .accessibilityLabel(preset.name.capitalized)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

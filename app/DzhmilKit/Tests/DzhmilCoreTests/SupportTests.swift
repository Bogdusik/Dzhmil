import Foundation
import Testing
@testable import DzhmilCore

@Suite(.serialized) struct KeychainStoreTests {
    let store = KeychainStore(service: "com.bogdusik.dzhmil.tests", account: "anthropic-api-key")

    @Test func saveReadDelete() throws {
        try? store.delete()
        #expect(store.read() == nil)
        try store.save("sk-test-1")
        #expect(store.read() == "sk-test-1")
        try store.save("sk-test-2")
        #expect(store.read() == "sk-test-2")
        try store.delete()
        #expect(store.read() == nil)
    }
}

@Suite struct AppSettingsTests {
    func defaults() -> UserDefaults {
        let name = "dzhmil.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func defaultValues() {
        let s = AppSettings()
        #expect(s.model == "claude-opus-5-5")
        #expect(s.effort == "low")
        #expect(s.chattiness == .normal)
        #expect(s.voiceEnabled)
        #expect(s.voiceVolume == 0.8)
        #expect(!s.propellerSound)
        #expect(!s.launchAtLogin)
        #expect(AppSettings.models == ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"])
        #expect(AppSettings.efforts == ["low", "medium", "high"])
    }

    @Test func roundTrip() {
        let d = defaults()
        var s = AppSettings()
        s.model = "claude-haiku-5-5"
        s.chattiness = .rare
        s.propellerSound = true
        s.save(to: d)
        #expect(AppSettings.load(from: d) == s)
    }

    @Test func garbageFallsBackToDefaults() {
        let d = defaults()
        d.set(Data("not json".utf8), forKey: AppSettings.key)
        #expect(AppSettings.load(from: d) == AppSettings())
        #expect(AppSettings.load(from: defaults()) == AppSettings())
    }

    @Test func chattinessGaps() {
        #expect(Chattiness.rare.minGap == 7200)
        #expect(Chattiness.normal.minGap == 2700)
        #expect(Chattiness.often.minGap == 1200)
    }
}

@Suite struct ProfileStoreTests {
    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dzhmil-\(UUID().uuidString)")
    }

    @Test func createsTemplateOnFirstLoad() throws {
        let store = ProfileStore(directory: tempDir())
        #expect(store.load() == "Меня зовут Богдан.\nЛюблю FPV-дроны и программирование.\n")
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(store.fileURL.lastPathComponent == "profile.md")
    }

    @Test func saveAndLoad() throws {
        let store = ProfileStore(directory: tempDir())
        try store.save("Новый профиль")
        #expect(store.load() == "Новый профиль")
    }

    @Test func defaultDirectoryIsApplicationSupport() {
        #expect(ProfileStore.defaultDirectory.path.hasSuffix("Library/Application Support/Dzhmil"))
    }
}

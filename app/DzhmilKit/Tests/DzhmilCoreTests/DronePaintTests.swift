import Foundation
import Testing
@testable import DzhmilCore

private func luminance(_ hex: UInt32) -> Double {
    func channel(_ shift: UInt32) -> Double {
        let c = Double((hex >> shift) & 0xFF) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
}

private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
    let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
    return (high + 0.05) / (low + 0.05)
}

private let extremes: [UInt32] = [0x000000, 0xFFFFFF, 0x0A0A40, 0xFFFF00]

@Suite struct DronePaintTests {
    @Test func turquoiseKeepsTheOriginalLook() {
        let p = DronePaint(DronePaint.turquoise)
        #expect([p.body, p.belly, p.shine, p.eye, p.button, p.accent] == [0x00D4AA, 0x009C82, 0x7DF3D8, 0x8CFFE4, 0x008F74, 0x00D4AA])
    }

    @Test(arguments: DroneColorPreset.all.map(\.hex).filter { $0 != DronePaint.turquoise })
    func shadesFollowTheChosenColor(_ hex: UInt32) {
        let p = DronePaint(hex)
        #expect(p.body == hex)
        #expect(luminance(p.belly) < luminance(p.body))
        #expect(luminance(p.shine) > luminance(p.body))
    }

    @Test(arguments: DroneColorPreset.all.map(\.hex) + extremes)
    func everyColorStaysReadable(_ hex: UInt32) {
        let p = DronePaint(hex)
        #expect(contrast(p.eye, 0x0A1B20) >= 7, "eyes on the visor")
        #expect(contrast(p.button, 0xFFFFFF) >= 3.9, "white text on the button")
        #expect(contrast(p.accent, 0x0A1B20) >= 3, "pointer on a dark screen")
    }

    @Test func presetsAreDistinctAndNamed() {
        let presets = DroneColorPreset.all
        #expect(presets.count >= 6)
        #expect(presets.first?.hex == DronePaint.turquoise)
        #expect(Set(presets.map(\.hex)).count == presets.count)
        #expect(Set(presets.map(\.name)).count == presets.count)
        for preset in presets { #expect(DronePaint.name(of: preset.hex) == preset.name) }
    }

    @Test(arguments: [(UInt32(0xE01010), "red"), (0x1030C0, "blue"), (0x20A030, "green"), (0x101010, "black"), (0xF8F8F8, "white"), (0x808080, "grey"),
                      (0xF07000, "orange"), (0xE8D000, "yellow"), (0x8020C0, "purple"), (0xF030A0, "pink"), (0x00C8B0, "turquoise")])
    func customColorsGetAPlainName(_ hex: UInt32, _ name: String) {
        #expect(DronePaint.name(of: hex) == name)
    }
}

@Suite struct DroneColorSettingsTests {
    @Test func turquoiseByDefaultAndSurvivesSaving() throws {
        var s = AppSettings()
        #expect(s.droneColor == DronePaint.turquoise)
        #expect(s.conversation.color == "turquoise")
        s.droneColor = 0xFF5FA2
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(restored.droneColor == 0xFF5FA2)
        #expect(restored.conversation.color == "pink")
    }

    @Test(arguments: [#"{}"#, #"{"droneColor":"red"}"#, #"{"droneColor":99999999}"#, #"{"droneColor":-1}"#])
    func badStoredColorFallsBack(_ json: String) throws {
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).droneColor == DronePaint.turquoise)
    }

    @Test func dzhmilKnowsItsColor() {
        #expect(PromptBuilder.system(profile: "").contains("small turquoise quadcopter"))
        #expect(PromptBuilder.system(profile: "", color: "pink").contains("small pink quadcopter"))
        #expect(PromptBuilder.proactive(profile: "", color: "pink").contains("small pink quadcopter"))
    }

    @Test func changingColorStartsAFreshSession() async {
        let client = FakeChatClient([Fixtures.text("Hi."), Fixtures.text("I'm pink.")])
        let color = ProfileBox("turquoise")
        let conversation = Conversation(client: client, executor: ToolExecutor(tools: [], confirmer: ScriptedConfirmer(mode: .no)),
                                        settings: { ConversationSettings(model: "claude-opus-5-5", effort: "low", color: color.value) },
                                        profile: { "" })
        for await _ in await conversation.send("hello") {}
        color.value = "pink"
        for await _ in await conversation.send("what colour are you?") {}
        #expect(client.requests[1].system.contains("small pink quadcopter"))
        #expect(client.requests[1].messages.count == 1)
    }
}

import Foundation
import Testing
@testable import DzhmilCore

@Suite struct DroneLookTests {
    @Test func originalLookByDefault() {
        #expect(AppSettings().look == DroneLook(body: DronePaint.turquoise, arms: 0x20343A, propellers: 0x20343A))
        #expect(AppSettings().look == DroneLook())
    }

    @Test func eachPartIsSavedSeparately() throws {
        var s = AppSettings()
        s.armColor = 0xFFFFFF
        s.propellerColor = 0xFF5FA2
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(restored.look == DroneLook(body: DronePaint.turquoise, arms: 0xFFFFFF, propellers: 0xFF5FA2))
    }

    @Test(arguments: [#"{"droneColor":16736162}"#, #"{"droneColor":16736162,"armColor":"red","propellerColor":99999999}"#])
    func missingOrBadPartColorsStayDark(_ json: String) throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.look == DroneLook(body: 0xFF5FA2))
    }

    @Test func partPresetsStartWithTheOriginalDark() {
        let parts = DroneColorPreset.parts
        #expect(parts.first?.hex == DronePaint.frame)
        #expect(parts.contains { $0.hex == 0xFFFFFF })
        #expect(Set(parts.map(\.hex)).count == parts.count)
        #expect(Set(parts.map(\.name)).count == parts.count)
        #expect(parts.count <= 9)
    }
}

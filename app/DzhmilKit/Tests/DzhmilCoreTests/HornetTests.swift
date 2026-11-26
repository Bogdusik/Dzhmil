import AVFoundation
import Foundation
import Testing
@testable import DzhmilCore

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -1920, y: 200, width: 1920, height: 1080),
                       CGRect(x: 0, y: 0, width: 3440, height: 1440)]
private let dt = 1.0 / 60

@Suite struct JetFlightTests {
    func home(_ screen: CGRect) -> CGPoint { CGPoint(x: screen.maxX - 120, y: screen.minY + 90) }

    @Test func takesOffUpwardsAndGetsFast() {
        let screen = screens[0]
        var jet = JetFlight(home: home(screen), screen: screen)
        var rng = SeededGenerator(state: 1)
        #expect(jet.position == home(screen))
        #expect(jet.heading == .pi / 2)
        #expect(jet.phase == .cruising)
        for _ in 0..<60 { jet.step(dt: dt, using: &rng) }
        #expect(jet.speed >= 700)
        #expect(jet.position.y > home(screen).y)
    }

    @Test(arguments: 1...12)
    func turnsSmoothlyAndStaysNearTheScreen(_ seed: Int) {
        let screen = screens[seed % screens.count]
        var jet = JetFlight(home: home(screen), screen: screen)
        var rng = SeededGenerator(state: UInt64(seed))
        let limit = screen.insetBy(dx: -JetFlight.margin - 1, dy: -JetFlight.margin - 1)
        for _ in 0..<(Int(JetFlight.duration / dt) - 1) {
            let before = jet.heading
            jet.step(dt: dt, using: &rng)
            var change = jet.heading - before
            change = atan2(sin(change), cos(change))
            #expect(abs(change) <= JetFlight.turnRate * dt + 1e-9)
            #expect(limit.contains(jet.position))
        }
        #expect(jet.phase == .cruising)
    }

    @Test func sometimesLeavesTheScreenAndComesBackFromTheOtherSide() {
        var wraps = 0
        for seed in 1...40 {
            var jet = JetFlight(home: home(screens[0]), screen: screens[0])
            var rng = SeededGenerator(state: UInt64(seed))
            for _ in 0..<Int(20 / dt) {
                let before = jet.position
                jet.step(dt: dt, using: &rng)
                if jet.wrapped {
                    wraps += 1
                    #expect(hypot(jet.position.x - before.x, jet.position.y - before.y) > 500)
                }
            }
        }
        #expect(wraps > 0)
    }

    @Test(arguments: 1...30)
    func comesHomeAfterItsTimeIsUp(_ seed: Int) {
        let screen = screens[seed % screens.count]
        var jet = JetFlight(home: home(screen), screen: screen, duration: 6)
        var rng = SeededGenerator(state: UInt64(seed))
        var elapsed = 0.0
        while jet.phase != .home, elapsed < 20 {
            jet.step(dt: dt, using: &rng)
            elapsed += dt
        }
        #expect(jet.phase == .home)
        #expect(jet.position == home(screen))
        #expect(elapsed > 6)
        #expect(elapsed < 15)
    }

    @Test func canBeCalledHomeEarlyAndThenStaysThere() {
        var jet = JetFlight(home: home(screens[0]), screen: screens[0])
        var rng = SeededGenerator(state: 7)
        for _ in 0..<120 { jet.step(dt: dt, using: &rng) }
        jet.comeHome()
        #expect(jet.phase == .returning)
        for _ in 0..<Int(9 / dt) { jet.step(dt: dt, using: &rng) }
        #expect(jet.phase == .home)
        #expect(jet.speed == 0)
        jet.step(dt: dt, using: &rng)
        #expect(jet.position == home(screens[0]))
    }
}

@Suite struct HornetSynthTests {
    func render(_ synth: HornetSynth, seconds: Double) -> [Float] {
        let rate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * seconds))!
        buffer.frameLength = buffer.frameCapacity
        var silence = ObjCBool(false)
        var time = AudioTimeStamp()
        _ = synth.renderBlock(sampleRate: rate)(&silence, &time, buffer.frameLength, buffer.mutableAudioBufferList)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    func loudness(_ samples: [Float]) -> Float {
        (samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count)).squareRoot()
    }

    @Test func silentUntilAsked() {
        #expect(render(HornetSynth(), seconds: 0.2).allSatisfy { $0 == 0 })
    }

    @Test func transformationClanksThenFadesOut() {
        let synth = HornetSynth()
        synth.clank()
        let hit = render(synth, seconds: 0.8)
        #expect(loudness(hit) > 0.01)
        #expect(hit.allSatisfy { abs($0) <= 1 })
        _ = render(synth, seconds: 1.5)
        #expect(loudness(render(synth, seconds: 0.2)) < 0.001)
    }

    @Test func engineFollowsItsThrottle() {
        let synth = HornetSynth()
        synth.setThrottle(1)
        _ = render(synth, seconds: 0.5)
        let full = loudness(render(synth, seconds: 0.5))
        #expect(full > 0.01 && full < 0.2)
        synth.setThrottle(0)
        _ = render(synth, seconds: 1)
        #expect(loudness(render(synth, seconds: 0.2)) < 0.001)
    }
}

@Suite struct TransformToolTests {
    func tools(_ transform: (@Sendable () async -> Bool)?) -> [any Tool] {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return MacToolbox.all(timers: TimerStore(file: file), transform: transform)
    }

    @Test func offeredOnlyWhenTheAppCanTransform() {
        #expect(!tools(nil).contains { $0.name == "transform_into_hornet" })
        #expect(tools({ true }).contains { $0.name == "transform_into_hornet" })
    }

    @Test func asksTheAppAndRequestsATheatricalLine() async throws {
        let calls = Counter()
        let tool = try #require(tools({ await calls.increment(); return true }).first { $0.name == "transform_into_hornet" })
        #expect(tool.risk(for: [:]) == .safe)
        let result = try await tool.run([:])
        #expect(result.contains("Hornet"))
        #expect(await calls.value == 1)
    }

    @Test func saysWhyItStayedGrounded() async throws {
        let tool = try #require(tools({ false }).first { $0.name == "transform_into_hornet" })
        await #expect(throws: ToolError.self) { try await tool.run([:]) }
    }
}

@Suite struct HornetSettingsTests {
    @Test func soundIsOnByDefaultAndCanBeTurnedOff() throws {
        var s = AppSettings()
        #expect(s.hornetSound)
        s.hornetSound = false
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s)).hornetSound == false)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).hornetSound)
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import DzhmilCore

final class PointRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _points: [PointRequest] = []
    let accept: Bool
    init(accept: Bool = true) { self.accept = accept }
    var points: [PointRequest] { lock.withLock { _points } }
    func record(_ p: PointRequest) -> Bool {
        lock.withLock { _points.append(p) }
        return accept
    }
}

@Suite struct ScreenPointMapperTests {
    @Test func scalesPixelsIntoTheCapturedRectAndFlipsY() {
        let frame = ScreenshotFrame(rect: CGRect(x: 100, y: 50, width: 800, height: 600), pixelWidth: 1600, pixelHeight: 1200, takenAt: Date())
        let p = ScreenPointMapper.appKitPoint(pixel: CGPoint(x: 400, y: 300), frame: frame, primaryHeight: 1000)
        #expect(p == CGPoint(x: 300, y: 800))
    }

    @Test func cornersMapToRectCorners() {
        let frame = ScreenshotFrame(rect: CGRect(x: 0, y: 0, width: 1512, height: 982), pixelWidth: 1568, pixelHeight: 1018, takenAt: Date())
        let topLeft = ScreenPointMapper.appKitPoint(pixel: .zero, frame: frame, primaryHeight: 982)
        let bottomRight = ScreenPointMapper.appKitPoint(pixel: CGPoint(x: 1568, y: 1018), frame: frame, primaryHeight: 982)
        #expect(topLeft == CGPoint(x: 0, y: 982))
        #expect(abs(bottomRight.x - 1512) < 0.001 && abs(bottomRight.y) < 0.001)
    }

    @Test func secondDisplayAboveMainUsesGlobalCoordinates() {
        let frame = ScreenshotFrame(rect: CGRect(x: 0, y: -1080, width: 1920, height: 1080), pixelWidth: 1920, pixelHeight: 1080, takenAt: Date())
        let p = ScreenPointMapper.appKitPoint(pixel: CGPoint(x: 960, y: 540), frame: frame, primaryHeight: 900)
        #expect(p == CGPoint(x: 960, y: 1440))
    }
}

@Suite struct PointerLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1500, height: 900)
    let drone = CGSize(width: 124, height: 93)

    @Test func dronePerchesOnTheRoomierSideAbove() {
        let right = PointerLayout.droneSpot(target: CGPoint(x: 1200, y: 400), visibleFrame: screen, droneSize: drone)
        #expect(right.x < 1200 && right.y > 400)
        let left = PointerLayout.droneSpot(target: CGPoint(x: 300, y: 400), visibleFrame: screen, droneSize: drone)
        #expect(left.x > 300 && left.y > 400)
    }

    @Test func goesBelowWhenTargetIsNearTheTop() {
        let spot = PointerLayout.droneSpot(target: CGPoint(x: 700, y: 870), visibleFrame: screen, droneSize: drone)
        #expect(spot.y < 870)
    }

    @Test func staysOnScreen() {
        for target in [CGPoint(x: 2, y: 2), CGPoint(x: 1498, y: 898), CGPoint(x: 1498, y: 2), CGPoint(x: 2, y: 898)] {
            let spot = PointerLayout.droneSpot(target: target, visibleFrame: screen, droneSize: drone)
            #expect(spot.x - drone.width / 2 >= screen.minX && spot.x + drone.width / 2 <= screen.maxX)
            #expect(spot.y - drone.height / 2 >= screen.minY && spot.y + drone.height / 2 <= screen.maxY)
        }
    }

    @Test func arrowRunsBetweenTheEdges() throws {
        let a = try #require(PointerLayout.arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), droneRadius: 40, ringRadius: 20))
        #expect(a.start == CGPoint(x: 40, y: 0))
        #expect(a.end == CGPoint(x: 80, y: 0))
    }

    @Test func arcBowsUpwardFromTheMiddle() {
        let start = CGPoint(x: 0, y: 0), end = CGPoint(x: 100, y: 0)
        let c = PointerLayout.arcControl(from: start, to: end)
        #expect(abs(c.x - 50) < 0.001)
        #expect(abs(c.y - 22) < 0.001)
        let down = PointerLayout.arcControl(from: end, to: start)
        #expect(abs(down.y - 22) < 0.001)
    }

    @Test func verticalArcBowsSideways() {
        let c = PointerLayout.arcControl(from: CGPoint(x: 0, y: 100), to: .zero)
        #expect(abs(c.y - 50) < 0.001)
        #expect(abs(abs(c.x) - 22) < 0.001)
    }

    @Test func noArrowWhenTooClose() {
        #expect(PointerLayout.arrow(from: .zero, to: CGPoint(x: 50, y: 0), droneRadius: 40, ringRadius: 20) == nil)
    }
}

@Suite struct PointAtToolTests {
    let shotRect = CGRect(x: 200, y: 100, width: 400, height: 300)

    func tools(_ recorder: PointRecorder, rect: CGRect? = nil, now: @escaping @Sendable () -> Date = { Date() }) -> (look: any Tool, point: any Tool) {
        let all = MacToolbox.all(timers: TimerStore(), screen: FakeCapturer(rect: rect ?? shotRect),
                                 pointer: { recorder.record($0) }, now: now)
        return (all.first { $0.name == "look_at_screen" }!, all.first { $0.name == "point_at" }!)
    }

    @Test func pointsAtTheMappedSpotOfTheLatestScreenshot() async throws {
        let recorder = PointRecorder()
        let (look, point) = tools(recorder)
        let shot = try await look.runRich(["target": "window"])
        #expect(shot.text.contains("400×300"))
        let out = try await point.run(["x": 100, "y": 150, "label": "Кнопка Run"])
        #expect(out.contains("Кнопка Run"))
        let primary = CGDisplayBounds(CGMainDisplayID()).height
        #expect(recorder.points == [PointRequest(point: CGPoint(x: 300, y: primary - 250), label: "Кнопка Run")])
        #expect(point.risk(for: ["x": 1, "y": 1, "label": "x"]) == .safe)
    }

    @Test func refusesWithoutAScreenshot() async {
        let recorder = PointRecorder()
        let (_, point) = tools(recorder)
        await #expect(throws: ToolError.self) { try await point.run(["x": 10, "y": 10, "label": "x"]) }
        #expect(recorder.points.isEmpty)
    }

    @Test func refusesPointsOutsideTheImage() async throws {
        let recorder = PointRecorder()
        let (look, point) = tools(recorder)
        _ = try await look.runRich(["target": "window"])
        for (x, y) in [(-1, 10), (10, -1), (401, 10), (10, 301)] {
            await #expect(throws: ToolError.self) { try await point.run(["x": .number(Double(x)), "y": .number(Double(y)), "label": "x"]) }
        }
        #expect(recorder.points.isEmpty)
    }

    @Test func refusesAStaleScreenshot() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000_000))
        let recorder = PointRecorder()
        let (look, point) = tools(recorder, now: { clock.now })
        _ = try await look.runRich(["target": "window"])
        clock.advance(11 * 60)
        await #expect(throws: ToolError.self) { try await point.run(["x": 10, "y": 10, "label": "x"]) }
        #expect(recorder.points.isEmpty)
    }

    @Test func refusesWhenTheCaptureHasNoGeometry() async throws {
        let recorder = PointRecorder()
        let (look, point) = tools(recorder, rect: .zero)
        _ = try await look.runRich(["target": "window"])
        await #expect(throws: ToolError.self) { try await point.run(["x": 10, "y": 10, "label": "x"]) }
    }

    @Test func reportsWhenTheDroneCannotShow() async throws {
        let recorder = PointRecorder(accept: false)
        let (look, point) = tools(recorder)
        _ = try await look.runRich(["target": "window"])
        do {
            _ = try await point.run(["x": 10, "y": 10, "label": "x"])
            Issue.record("expected an error")
        } catch {
            #expect(error.localizedDescription.contains("спрятан"))
        }
    }
}

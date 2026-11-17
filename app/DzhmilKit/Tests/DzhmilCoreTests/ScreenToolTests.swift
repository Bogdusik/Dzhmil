import CoreGraphics
import Foundation
import Testing
@testable import DzhmilCore

final class FakeCapturer: ScreenCapturer, @unchecked Sendable {
    private let lock = NSLock()
    private var _log: [String] = []
    let windowError: ScreenCaptureError?
    let screenError: ScreenCaptureError?
    let rect: CGRect

    init(windowError: ScreenCaptureError? = nil, screenError: ScreenCaptureError? = nil,
         rect: CGRect = CGRect(x: 0, y: 0, width: 400, height: 300)) {
        self.windowError = windowError
        self.screenError = screenError
        self.rect = rect
    }

    var log: [String] { lock.withLock { _log } }
    func note(_ s: String) { lock.withLock { _log.append(s) } }

    func capture(_ target: CaptureTarget) async throws -> CapturedImage {
        note("capture:\(target.rawValue)")
        if target == .window, let e = windowError { throw e }
        if target == .screen, let e = screenError { throw e }
        return CapturedImage(image: solidImage(400, 300), appName: "Safari", windowTitle: "Apple", rect: rect)
    }
}

@Suite struct ScreenToolTests {
    func lookTool(_ capturer: FakeCapturer) -> any Tool {
        MacToolbox.all(timers: TimerStore(), screen: capturer, beforeCapture: { capturer.note("hook"); return true })
            .first { $0.name == "look_at_screen" }!
    }

    @Test func lookAtScreenReturnsImageAndCaption() async throws {
        let out = try await lookTool(FakeCapturer()).runRich(["target": "window"])
        #expect(out.images.count == 1)
        #expect(out.images.first?.mediaType == "image/jpeg")
        #expect(out.text == "Скриншот окна: Safari — Apple. Размер картинки 400×300 px.")
    }

    @Test func beforeCaptureRunsFirst() async throws {
        let capturer = FakeCapturer()
        _ = try await lookTool(capturer).runRich(["target": "window"])
        #expect(capturer.log == ["hook", "capture:window"])
    }

    @Test func deniedPermissionExplainsWhereToEnable() async {
        let tool = lookTool(FakeCapturer(windowError: .permissionDenied, screenError: .permissionDenied))
        do {
            _ = try await tool.runRich(["target": "window"])
            Issue.record("expected an error")
        } catch {
            #expect(error.localizedDescription.contains("Запись экрана"))
        }
    }

    @Test func windowFallsBackToScreen() async throws {
        let capturer = FakeCapturer(windowError: .nothingToCapture)
        let out = try await lookTool(capturer).runRich(["target": "window"])
        #expect(capturer.log == ["hook", "capture:window", "capture:screen"])
        #expect(out.images.count == 1)
        #expect(out.text.hasPrefix("Скриншот экрана"))
    }

    @Test func refusedIndicatorPreventsCapture() async {
        let capturer = FakeCapturer()
        let tool = MacToolbox.all(timers: TimerStore(), screen: capturer, beforeCapture: { capturer.note("hook"); return false })
            .first { $0.name == "look_at_screen" }!
        do {
            _ = try await tool.runRich(["target": "window"])
            Issue.record("expected refusal")
        } catch {
            #expect(error.localizedDescription.contains("спрятан"))
        }
        #expect(capturer.log == ["hook"])
    }

    @Test func cancellationDuringIndicatorPreventsCapture() async throws {
        let capturer = FakeCapturer()
        let tool = MacToolbox.all(timers: TimerStore(), screen: capturer, beforeCapture: {
            capturer.note("hook")
            try? await Task.sleep(for: .milliseconds(300))
            return true
        }).first { $0.name == "look_at_screen" }!
        let task = Task { try await tool.runRich(["target": "window"]) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = try? await task.value
        #expect(capturer.log == ["hook"])
    }

    @Test func schemaAndRisk() {
        let tool = lookTool(FakeCapturer())
        #expect(tool.inputSchema["properties"]?["target"]?["enum"] == ["window", "screen"])
        #expect(tool.risk(for: ["target": "screen"]) == .safe)
    }

    @Test func toolboxWithScreenHasThirteenTools() {
        let names = MacToolbox.all(timers: TimerStore(), screen: FakeCapturer()).map(\.name)
        #expect(names.count == 13)
        #expect(names.contains("look_at_screen"))
        #expect(MacToolbox.all(timers: TimerStore()).count == 12)
        let withPointer = MacToolbox.all(timers: TimerStore(), screen: FakeCapturer(), pointer: { _ in true }).map(\.name)
        #expect(withPointer.count == 14)
        #expect(withPointer.contains("point_at"))
    }
}

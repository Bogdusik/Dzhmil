#if DEBUG
import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import DzhmilCore

@MainActor
final class DemoDirector {
    private let companion: Companion
    private let outputDirectory: URL
    private var recorder: ScreenRecorder?

    init(companion: Companion, outputDirectory: URL) {
        self.companion = companion
        self.outputDirectory = outputDirectory
    }

    private var director: DroneDirector { companion.director }

    func run(only: Set<String>) async {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let scenes: [(String, () async -> Void)] = [
            ("hero", hero), ("pet", pet), ("emotions", emotions),
            ("voice", voice), ("confirm", confirm), ("error", errorHelp), ("pointer", pointer),
        ]
        for (name, scene) in scenes where only.isEmpty || only.contains(name) {
            print("scene \(name)")
            await reset()
            let url = outputDirectory.appendingPathComponent("\(name).mov")
            try? FileManager.default.removeItem(at: url)
            let recorder = ScreenRecorder(url: url)
            do { try await recorder.start() } catch { print("record failed: \(error)"); continue }
            self.recorder = recorder
            await scene()
            await recorder.stop()
            self.recorder = nil
        }
        print("done")
    }

    private static let allowedApps: Set<String> = ["com.apple.finder", "com.apple.calculator", "com.apple.systempreferences"]

    private func hideOtherApps() {
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != me && !Self.allowedApps.contains(app.bundleIdentifier ?? "") {
            app.hide()
        }
    }

    private func reset() async {
        hideOtherApps()
        companion.show(nil)
        director.clearPointer()
        await companion.conversation.resetSession()
        guard let frame = NSScreen.main?.visibleFrame else { return }
        director.flight.place(at: CGPoint(x: frame.midX, y: frame.minY + 330))
        director.model.eyeOffset = .zero
        await pause(1)
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func moveCursor(to point: CGPoint, over seconds: Double = 0.6) async {
        guard let height = NSScreen.screens.first?.frame.height else { return }
        let start = NSEvent.mouseLocation
        let steps = max(1, Int(seconds * 60))
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let eased = t * t * (3 - 2 * t)
            let x = start.x + (point.x - start.x) * eased
            let y = start.y + (point.y - start.y) * eased
            CGWarpMouseCursorPosition(CGPoint(x: x, y: height - y))
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func waitForReply(timeout: Double = 60) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            hideOtherApps()
            if companion.replyFinished { return }
        }
    }

    private func ask(_ text: String) async {
        companion.submitText(text)
        await pause(0.3)
        await waitForReply()
    }

    private func hero() async {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        let center = director.flight.droneCenter
        await moveCursor(to: CGPoint(x: center.x - 330, y: center.y + 60), over: 0.9)
        await pause(0.6)
        await moveCursor(to: CGPoint(x: center.x + 330, y: center.y - 20), over: 1.4)
        await pause(0.5)
        director.flight.fling(velocity: CGVector(dx: 700, dy: 160), to: CGPoint(x: min(frame.maxX - 150, center.x + 320), y: center.y + 70)) { [weak self] in
            self?.director.model.play(.steady(fromLeft: true))
        }
        await pause(2.8)
        director.flight.fling(velocity: CGVector(dx: -800, dy: -60), to: CGPoint(x: max(frame.minX + 150, center.x - 340), y: center.y - 20)) { [weak self] in
            self?.director.model.play(.steady(fromLeft: false))
        }
        await pause(2.8)
    }

    private func pet() async {
        let c = director.flight.droneCenter
        await moveCursor(to: CGPoint(x: c.x - 22, y: c.y), over: 0.8)
        await pause(0.3)
        for i in 0..<30 {
            let x = c.x + 22 * sin(Double(i) * 0.62)
            guard let height = NSScreen.screens.first?.frame.height else { return }
            CGWarpMouseCursorPosition(CGPoint(x: x, y: height - c.y))
            try? await Task.sleep(for: .milliseconds(50))
        }
        await pause(2.2)
        await moveCursor(to: CGPoint(x: c.x + 400, y: c.y - 120), over: 0.8)
        await pause(1.2)
    }

    private func emotions() async {
        for emotion in [Emotion.happy, .laugh, .surprised, .thinking, .sad] {
            director.model.play(.emotion(emotion))
            await pause(2.1)
        }
    }

    private func voice() async {
        await ask("How is my Mac doing? Give me the short version.")
        await pause(3)
    }

    private func confirm() async {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        _ = try? await NSWorkspace.shared.openApplication(at: calculator, configuration: NSWorkspace.OpenConfiguration())
        await pause(1.5)
        companion.submitText("Please quit Calculator.")
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if case .confirm? = companion.model.bubble { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        await pause(2)
        companion.confirmer.answerFromButton(true)
        await pause(1)
        await waitForReply()
        await pause(3)
    }

    private func errorHelp() async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("""
        error: cannot find 'userName' in scope
            print("Hello, \\(userName)")
                           ^~~~~~~~
        """, forType: .string)
        await pause(1)
        await ask("What's this error I just copied?")
        await pause(3)
        NSPasteboard.general.clearContents()
    }

    private func pointer() async {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Appearance-Settings.extension")!)
        await pause(3.5)
        await ask("Where do I switch between light and dark mode? Look at my screen and point at it.")
        await pause(4)
        companion.show(nil)
        await pause(0.8)
    }
}

final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "dzhmil.recorder")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var started = false

    init(url: URL) { self.url = url }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else { return }
        let width = (display.width / 2) * 2, height = (display.height / 2) * 2
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let writer = try AVAssetWriter(url: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        self.writer = writer
        self.input = input

        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        queue.sync {}
        input?.markAsFinished()
        await writer?.finishWriting()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let writer, let input else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete else { return }
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(sampleBuffer) }
    }
}
#endif

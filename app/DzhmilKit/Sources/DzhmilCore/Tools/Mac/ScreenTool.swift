import CoreGraphics
import Foundation

public enum CaptureTarget: String, Sendable {
    case window, screen
}

public struct CapturedImage: @unchecked Sendable {
    public var image: CGImage
    public var appName: String?
    public var windowTitle: String?
    public var rect: CGRect

    public init(image: CGImage, appName: String?, windowTitle: String?, rect: CGRect = .zero) {
        self.image = image
        self.appName = appName
        self.windowTitle = windowTitle
        self.rect = rect
    }
}

public enum ScreenCaptureError: Error, Equatable {
    case permissionDenied, nothingToCapture
}

public protocol ScreenCapturer: Sendable {
    func capture(_ target: CaptureTarget) async throws -> CapturedImage
}

struct LookAtScreenTool: SafeTool {
    static let deniedMessage = "I don't have Screen Recording access. Turn Dzhmil on in System Settings → Privacy & Security → Screen Recording, then restart me."

    let capturer: any ScreenCapturer
    let beforeCapture: @Sendable () async -> Bool
    var memory: ScreenshotMemory? = nil
    var now: @Sendable () -> Date = { Date() }
    let name = "look_at_screen"
    let description = "Take a screenshot to see the user's screen. window is the active window, screen is the whole screen. Call it only when the user asks you to look or asks about something on their screen."
    let inputSchema = Schema.object(["target": ["type": "string", "enum": ["window", "screen"], "description": "window or screen"]])

    func run(_ input: JSONValue) async throws -> String {
        try await runRich(input).text
    }

    func runRich(_ input: JSONValue) async throws -> ToolRichOutput {
        let requested = CaptureTarget(rawValue: input["target"]?.stringValue ?? "window") ?? .window
        guard await beforeCapture() else {
            throw ToolError.message("I'm hidden right now, so I can't show that I'm looking. Call me back and ask again.")
        }
        try Task.checkCancellation()
        do {
            let (shot, target) = try await capture(requested)
            let base64 = try ImageEncoder.jpegBase64(shot.image)
            let size = ImageEncoder.fittedSize(width: shot.image.width, height: shot.image.height)
            let frame = shot.rect.isEmpty ? nil
                : ScreenshotFrame(rect: shot.rect, pixelWidth: size.width, pixelHeight: size.height, takenAt: now())
            await memory?.remember(frame)
            let text = caption(shot, target) + ". Image size \(size.width)×\(size.height) px."
            return ToolRichOutput(text: text, images: [ToolImage(mediaType: "image/jpeg", base64: base64)])
        } catch ScreenCaptureError.permissionDenied {
            throw ToolError.message(Self.deniedMessage)
        } catch ScreenCaptureError.nothingToCapture {
            throw ToolError.message("Nothing to capture: there are no windows on screen.")
        }
    }

    private func capture(_ target: CaptureTarget) async throws -> (CapturedImage, CaptureTarget) {
        do {
            return (try await capturer.capture(target), target)
        } catch ScreenCaptureError.nothingToCapture where target == .window {
            return (try await capturer.capture(.screen), .screen)
        }
    }

    private func caption(_ shot: CapturedImage, _ target: CaptureTarget) -> String {
        switch target {
        case .window:
            let parts = [shot.appName, shot.windowTitle].compactMap { $0 }.filter { !$0.isEmpty }
            return "Window screenshot: " + (parts.isEmpty ? "untitled" : parts.joined(separator: " — "))
        case .screen:
            return "Screenshot of the screen" + (shot.appName.map { ". Active app: \($0)" } ?? "")
        }
    }
}

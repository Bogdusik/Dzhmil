import CoreGraphics
import Foundation

public enum CaptureTarget: String, Sendable {
    case window, screen
}

public struct CapturedImage: @unchecked Sendable {
    public var image: CGImage
    public var appName: String?
    public var windowTitle: String?

    public init(image: CGImage, appName: String?, windowTitle: String?) {
        self.image = image
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

public enum ScreenCaptureError: Error, Equatable {
    case permissionDenied, nothingToCapture
}

public protocol ScreenCapturer: Sendable {
    func capture(_ target: CaptureTarget) async throws -> CapturedImage
}

struct LookAtScreenTool: SafeTool {
    static let deniedMessage = "Нет доступа к записи экрана. Включи Джмиля в Системных настройках → Конфиденциальность и безопасность → Запись экрана, потом перезапусти меня."

    let capturer: any ScreenCapturer
    let beforeCapture: @Sendable () async -> Void
    let name = "look_at_screen"
    let description = "Сделать скриншот и посмотреть на экран пользователя. window — активное окно, screen — весь экран. Вызывай только когда пользователь просит посмотреть или спрашивает о том, что у него на экране."
    let inputSchema = Schema.object(["target": ["type": "string", "enum": ["window", "screen"], "description": "window или screen"]])

    func run(_ input: JSONValue) async throws -> String {
        try await runRich(input).text
    }

    func runRich(_ input: JSONValue) async throws -> ToolRichOutput {
        let requested = CaptureTarget(rawValue: input["target"]?.stringValue ?? "window") ?? .window
        await beforeCapture()
        do {
            let (shot, target) = try await capture(requested)
            let base64 = try ImageEncoder.jpegBase64(shot.image)
            return ToolRichOutput(text: caption(shot, target), images: [ToolImage(mediaType: "image/jpeg", base64: base64)])
        } catch ScreenCaptureError.permissionDenied {
            throw ToolError.message(Self.deniedMessage)
        } catch ScreenCaptureError.nothingToCapture {
            throw ToolError.message("Не нашёл, что снять: на экране нет окон.")
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
            return "Скриншот окна: " + (parts.isEmpty ? "без названия" : parts.joined(separator: " — "))
        case .screen:
            return "Скриншот экрана" + (shot.appName.map { ". Активное приложение: \($0)" } ?? "")
        }
    }
}

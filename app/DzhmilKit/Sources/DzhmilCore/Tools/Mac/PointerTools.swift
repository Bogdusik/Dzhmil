import CoreGraphics
import Foundation

public struct ScreenshotFrame: Equatable, Sendable {
    public var rect: CGRect
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var takenAt: Date

    public init(rect: CGRect, pixelWidth: Int, pixelHeight: Int, takenAt: Date) {
        self.rect = rect
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.takenAt = takenAt
    }
}

public actor ScreenshotMemory {
    public private(set) var latest: ScreenshotFrame?

    public init() {}

    public func remember(_ frame: ScreenshotFrame?) {
        latest = frame
    }
}

public enum ScreenPointMapper {
    public static func appKitPoint(pixel: CGPoint, frame: ScreenshotFrame, primaryHeight: CGFloat) -> CGPoint {
        let x = frame.rect.minX + pixel.x * frame.rect.width / CGFloat(max(1, frame.pixelWidth))
        let y = frame.rect.minY + pixel.y * frame.rect.height / CGFloat(max(1, frame.pixelHeight))
        return CGPoint(x: x, y: primaryHeight - y)
    }
}

public struct PointRequest: Equatable, Sendable {
    public var point: CGPoint
    public var label: String

    public init(point: CGPoint, label: String) {
        self.point = point
        self.label = label
    }
}

struct PointAtTool: SafeTool {
    static let maxAge: TimeInterval = 10 * 60

    let memory: ScreenshotMemory
    let pointer: @Sendable (PointRequest) async -> Bool
    var now: @Sendable () -> Date = { Date() }
    var primaryHeight: @Sendable () -> CGFloat = { CGDisplayBounds(CGMainDisplayID()).height }

    let name = "point_at"
    let description = "Показать пользователю место на экране: Джміль подлетит и укажет стрелкой. x и y — пиксели на последнем скриншоте из look_at_screen (от левого верхнего угла картинки). Вызывай, когда объясняешь, куда нажать, по одному шагу."
    let inputSchema = Schema.object([
        "x": Schema.integer("Пиксель по горизонтали на последнем скриншоте"),
        "y": Schema.integer("Пиксель по вертикали на последнем скриншоте"),
        "label": Schema.string("Короткая подпись, например «Кнопка Run»"),
    ])

    func run(_ input: JSONValue) async throws -> String {
        let x = try input.requiredInt("x")
        let y = try input.requiredInt("y")
        let label = try input.requiredString("label")
        guard let frame = await memory.latest else {
            throw ToolError.message("Сначала посмотри на экран через look_at_screen: координаты берутся с последнего скриншота.")
        }
        guard now().timeIntervalSince(frame.takenAt) <= Self.maxAge else {
            throw ToolError.message("Скриншот устарел. Посмотри на экран ещё раз через look_at_screen.")
        }
        guard (0...frame.pixelWidth).contains(x), (0...frame.pixelHeight).contains(y) else {
            throw ToolError.message("Точка вне скриншота: картинка \(frame.pixelWidth)×\(frame.pixelHeight) px.")
        }
        let point = ScreenPointMapper.appKitPoint(pixel: CGPoint(x: x, y: y), frame: frame, primaryHeight: primaryHeight())
        guard await pointer(PointRequest(point: point, label: label)) else {
            throw ToolError.message("Я сейчас спрятан и не могу показать. Позови меня и попроси ещё раз.")
        }
        return "Показываю на «\(label)»."
    }
}

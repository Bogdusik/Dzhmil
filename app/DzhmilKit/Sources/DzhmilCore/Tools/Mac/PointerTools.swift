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
    let description = "Show the user a spot on the screen: Dzhmil flies over and points at it with an arrow. x and y are pixels on the latest look_at_screen screenshot, from the top-left corner of the image. Use it when explaining where to click, one step at a time."
    let inputSchema = Schema.object([
        "x": Schema.integer("Horizontal pixel on the latest screenshot"),
        "y": Schema.integer("Vertical pixel on the latest screenshot"),
        "label": Schema.string("Short label, for example “Run button”"),
    ])

    func run(_ input: JSONValue) async throws -> String {
        let x = try input.requiredInt("x")
        let y = try input.requiredInt("y")
        let label = try input.requiredString("label")
        guard let frame = await memory.latest else {
            throw ToolError.message("Look at the screen with look_at_screen first: the coordinates come from the latest screenshot.")
        }
        guard now().timeIntervalSince(frame.takenAt) <= Self.maxAge else {
            throw ToolError.message("The screenshot is out of date. Look at the screen again with look_at_screen.")
        }
        guard (0...frame.pixelWidth).contains(x), (0...frame.pixelHeight).contains(y) else {
            throw ToolError.message("That point is outside the screenshot: the image is \(frame.pixelWidth)×\(frame.pixelHeight) px.")
        }
        let point = ScreenPointMapper.appKitPoint(pixel: CGPoint(x: x, y: y), frame: frame, primaryHeight: primaryHeight())
        guard await pointer(PointRequest(point: point, label: label)) else {
            throw ToolError.message("I'm hidden right now and can't show it. Call me back and ask again.")
        }
        return "Pointing at “\(label)”."
    }
}

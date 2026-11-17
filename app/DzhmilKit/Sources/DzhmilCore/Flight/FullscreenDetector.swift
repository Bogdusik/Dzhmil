import CoreGraphics

public enum FullscreenDetector {
    public struct Screen: Sendable {
        public var frame: CGRect
        public var topInset: CGFloat

        public init(frame: CGRect, topInset: CGFloat) {
            self.frame = frame
            self.topInset = topInset
        }
    }

    public static func matches(_ window: CGRect, screens: [Screen]) -> Bool {
        screens.contains { screen in
            let belowNotch = CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: screen.frame.height - screen.topInset)
            return [screen.frame, belowNotch].contains { close(window, $0) }
        }
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }
}

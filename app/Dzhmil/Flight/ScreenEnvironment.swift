import AppKit
import CoreGraphics
import DzhmilCore

@MainActor
enum ScreenEnvironment {
    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    static func geometry(for screen: NSScreen?) -> ScreenGeometry {
        let s = screen ?? NSScreen.main ?? NSScreen.screens[0]
        return ScreenGeometry(frame: s.frame, visibleFrame: s.visibleFrame)
    }

    static func currentScreen() -> ScreenGeometry {
        geometry(for: screen(containing: cursor()))
    }

    static func cursor() -> CGPoint {
        NSEvent.mouseLocation
    }

    static func secondsSinceUserInput() -> TimeInterval {
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    private static func windows() -> [[String: Any]] {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    }

    private static func bounds(_ w: [String: Any]) -> CGRect? {
        guard let dict = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict as CFDictionary)
    }

    static func isFrontmostFullscreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        let pid = app.processIdentifier
        let screens = NSScreen.screens.map(\.frame)
        for w in windows() {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = bounds(w) else { continue }
            let r = Coordinates.cgToAppKit(b, primaryScreenHeight: primaryHeight)
            if screens.contains(where: { abs($0.width - r.width) < 1 && abs($0.height - r.height) < 1 && abs($0.minX - r.minX) < 1 && abs($0.minY - r.minY) < 1 }) {
                return true
            }
        }
        return false
    }

    static func windowTops(on screen: ScreenGeometry) -> [CGRect] {
        let me = ProcessInfo.processInfo.processIdentifier
        return windows().compactMap { w in
            guard (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = bounds(w), b.width > 300, b.height > 150 else { return nil }
            let r = Coordinates.cgToAppKit(b, primaryScreenHeight: primaryHeight)
            guard screen.visibleFrame.intersects(r), r.maxY < screen.visibleFrame.maxY - 140 else { return nil }
            return r
        }
    }
}

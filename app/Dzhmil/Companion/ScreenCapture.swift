import AppKit
import ScreenCaptureKit
import DzhmilCore

final class SCKScreenCapturer: ScreenCapturer {
    func capture(_ target: CaptureTarget) async throws -> CapturedImage {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw ScreenCaptureError.permissionDenied
        }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenCaptureError.permissionDenied
        }
        let me = ProcessInfo.processInfo.processIdentifier
        let (frontPID, frontName, displayID) = await MainActor.run { () -> (pid_t?, String?, CGDirectDisplayID?) in
            let front = NSWorkspace.shared.frontmostApplication
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            let id = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return (front?.processIdentifier, front?.localizedName, id)
        }

        switch target {
        case .window:
            guard let pid = frontPID, pid != me, let pick = WindowPicker.pick(Self.zOrderedWindows(), pid: pid) else {
                throw ScreenCaptureError.nothingToCapture
            }
            let windows = pick.ids.compactMap { id in content.windows.first { $0.windowID == id } }
            guard let front = windows.first,
                  let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: pick.rect.midX, y: pick.rect.midY)) }) ?? content.displays.first else {
                throw ScreenCaptureError.nothingToCapture
            }
            let filter = SCContentFilter(display: display, including: windows)
            let source = pick.rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY).intersection(CGRect(origin: .zero, size: display.frame.size))
            let image = try await shoot(filter, sourceRect: source, showsCursor: false)
            return CapturedImage(image: image, appName: frontName, windowTitle: front.title, rect: pick.rect.intersection(display.frame))

        case .screen:
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw ScreenCaptureError.nothingToCapture
            }
            let mine = content.windows.filter { $0.owningApplication?.processID == me }
            let filter = SCContentFilter(display: display, excludingWindows: mine)
            let image = try await shoot(filter, sourceRect: nil, showsCursor: true)
            return CapturedImage(image: image, appName: frontPID == me ? nil : frontName, windowTitle: nil, rect: display.frame)
        }
    }

    static func zOrderedWindows() -> [WindowPicker.Window] {
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        return list.compactMap { w in
            guard let id = w[kCGWindowNumber as String] as? UInt32,
                  let pid = w[kCGWindowOwnerPID as String] as? Int32,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            return WindowPicker.Window(id: id, pid: pid, layer: w[kCGWindowLayer as String] as? Int ?? 0, frame: frame)
        }
    }

    private func shoot(_ filter: SCContentFilter, sourceRect: CGRect?, showsCursor: Bool) async throws -> CGImage {
        let scale = CGFloat(filter.pointPixelScale)
        let area = sourceRect ?? filter.contentRect
        let size = ImageEncoder.fittedSize(width: Int(area.width * scale), height: Int(area.height * scale))
        let config = SCStreamConfiguration()
        if let sourceRect { config.sourceRect = sourceRect }
        config.width = max(1, size.width)
        config.height = max(1, size.height)
        config.showsCursor = showsCursor
        config.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

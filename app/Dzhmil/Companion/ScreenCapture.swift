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
        let (frontPID, frontName, mouse, displayID) = await MainActor.run { () -> (pid_t?, String?, CGPoint, CGDirectDisplayID?) in
            let front = NSWorkspace.shared.frontmostApplication
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            let id = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return (front?.processIdentifier, front?.localizedName, mouse, id)
        }
        _ = mouse

        switch target {
        case .window:
            guard let pid = frontPID, pid != me else { throw ScreenCaptureError.nothingToCapture }
            let candidates = content.windows.filter {
                $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.isOnScreen
                    && $0.frame.width > 80 && $0.frame.height > 60
            }
            guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                throw ScreenCaptureError.nothingToCapture
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let image = try await shoot(filter, showsCursor: false)
            return CapturedImage(image: image, appName: frontName, windowTitle: window.title)

        case .screen:
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw ScreenCaptureError.nothingToCapture
            }
            let mine = content.windows.filter { $0.owningApplication?.processID == me }
            let filter = SCContentFilter(display: display, excludingWindows: mine)
            let image = try await shoot(filter, showsCursor: true)
            return CapturedImage(image: image, appName: frontPID == me ? nil : frontName, windowTitle: nil)
        }
    }

    private func shoot(_ filter: SCContentFilter, showsCursor: Bool) async throws -> CGImage {
        let scale = CGFloat(filter.pointPixelScale)
        let size = ImageEncoder.fittedSize(width: Int(filter.contentRect.width * scale), height: Int(filter.contentRect.height * scale))
        let config = SCStreamConfiguration()
        config.width = max(1, size.width)
        config.height = max(1, size.height)
        config.showsCursor = showsCursor
        config.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

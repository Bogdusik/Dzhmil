import AppKit

@MainActor
enum ScreenPrivacy {
    private static let key = "hideFromScreenSharing"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool, persist: Bool = true) {
        if persist { UserDefaults.standard.set(enabled, forKey: key) }
        NSApp.windows.forEach { apply(to: $0, enabled: enabled) }
    }

    static func apply(to window: NSWindow) {
        apply(to: window, enabled: isEnabled)
    }

    private static func apply(to window: NSWindow, enabled: Bool) {
        window.sharingType = enabled ? .none : .readOnly
    }
}

import AppKit
import DzhmilCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let companion: Companion
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var talkItem: NSMenuItem!
    private var quietItem: NSMenuItem!
    private var hideItem: NSMenuItem!
    private var screenItem: NSMenuItem!
    private var sharingItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    static let screenSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    init(companion: Companion) {
        self.companion = companion
        super.init()
        item.button?.image = Self.icon()
        item.button?.toolTip = "Dzhmil"
        menu.delegate = self

        talkItem = add("Talk", #selector(talk))
        add("Type…", #selector(write))
        menu.addItem(.separator())
        quietItem = add("Quiet Mode", #selector(toggleQuiet))
        hideItem = add("Hide", #selector(toggleHidden))
        sharingItem = add("Hide from Screen Sharing", #selector(toggleSharing))
        sharingItem.toolTip = "Asks macOS to keep Dzhmil out of screen sharing and recordings. Some apps may still capture it; sharing a single window always keeps it out."
        menu.addItem(.separator())
        screenItem = add("Allow Screen Access…", #selector(allowScreen))
        add("Settings…", #selector(openSettings), key: ",")
        updateItem = add("Check for Updates…", #selector(update))
        #if DEBUG
        add("State Gallery", #selector(openGallery))
        #endif
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        menu.addItem(i)
        return i
    }

    func menuWillOpen(_ menu: NSMenu) {
        talkItem.title = companion.isListening ? "Stop and Send" : "Talk"
        quietItem.state = companion.director.machine.quiet ? .on : .off
        hideItem.title = companion.director.isHidden ? "Show" : "Hide"
        sharingItem.state = ScreenPrivacy.isEnabled ? .on : .off
        screenItem.isHidden = CGPreflightScreenCaptureAccess()
        updateItem.title = companion.updates.available.map { "Update to \($0.version)…" } ?? "Check for Updates…"
    }

    @objc private func allowScreen() {
        Self.requestScreenAccess()
    }

    static func requestScreenAccess() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(screenSettingsURL)
        }
    }

    @objc private func talk() {
        if companion.director.isHidden { companion.setHidden(false) }
        companion.isListening ? companion.pttUp() : companion.pttDown()
    }

    @objc private func write() {
        if companion.director.isHidden { companion.setHidden(false) }
        companion.openTextInput()
    }

    @objc private func toggleQuiet() {
        companion.director.setQuiet(!companion.director.machine.quiet)
    }

    @objc private func toggleHidden() {
        companion.setHidden(!companion.director.isHidden)
    }

    @objc private func toggleSharing() {
        ScreenPrivacy.setEnabled(!ScreenPrivacy.isEnabled)
    }

    @objc private func update() {
        if companion.director.isHidden { companion.setHidden(false) }
        companion.updates.available == nil ? companion.updates.checkNow() : companion.updates.openUpdate()
    }

    @objc private func openSettings() {
        SettingsWindow.show(companion: companion)
    }

    #if DEBUG
    @objc private func openGallery() {
        StateGallery.show()
    }
    #endif

    static func icon() -> NSImage {
        let view = DroneLayerView(width: 24)
        view.apply(state: .hover)
        let image = view.renderImage(scale: 2) ?? NSImage(systemSymbolName: "fanblades", accessibilityDescription: nil)!
        image.size = NSSize(width: 24, height: 18)
        image.isTemplate = true
        return image
    }
}

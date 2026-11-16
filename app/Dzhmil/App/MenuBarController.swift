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

    init(companion: Companion) {
        self.companion = companion
        super.init()
        item.button?.image = Self.icon()
        item.button?.toolTip = "Джміль"
        menu.delegate = self

        talkItem = add("Поговорить", #selector(talk))
        add("Написать…", #selector(write))
        menu.addItem(.separator())
        quietItem = add("Тихий режим", #selector(toggleQuiet))
        hideItem = add("Спрятать", #selector(toggleHidden))
        menu.addItem(.separator())
        add("Настройки…", #selector(openSettings), key: ",")
        #if DEBUG
        add("Галерея состояний", #selector(openGallery))
        #endif
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        talkItem.title = companion.isListening ? "Закончить и отправить" : "Поговорить"
        quietItem.state = companion.director.machine.quiet ? .on : .off
        hideItem.title = companion.director.isHidden ? "Показать" : "Спрятать"
    }

    @objc private func talk() {
        if companion.director.isHidden { companion.director.setHidden(false) }
        companion.isListening ? companion.pttUp() : companion.pttDown()
    }

    @objc private func write() {
        if companion.director.isHidden { companion.director.setHidden(false) }
        companion.openTextInput()
    }

    @objc private func toggleQuiet() {
        companion.director.setQuiet(!companion.director.machine.quiet)
    }

    @objc private func toggleHidden() {
        companion.director.setHidden(!companion.director.isHidden)
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

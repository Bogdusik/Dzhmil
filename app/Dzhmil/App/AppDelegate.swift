import AppKit
import DzhmilCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    let director = DroneDirector()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--render-states"), i + 1 < CommandLine.arguments.count {
            StateGallery.renderAll(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            NSApp.terminate(nil)
            return
        }
        #endif
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "fanblades", accessibilityDescription: "Джміль")
        let menu = NSMenu()
        #if DEBUG
        let gallery = NSMenuItem(title: "Галерея состояний", action: #selector(showGallery), keyEquivalent: "")
        gallery.target = self
        menu.addItem(gallery)
        menu.addItem(.separator())
        #endif
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--idle-seconds"), i + 1 < CommandLine.arguments.count {
            director.idleOverride = TimeInterval(CommandLine.arguments[i + 1])
        }
        #endif
        director.start()
    }

    #if DEBUG
    @objc private func showGallery() {
        StateGallery.show()
    }
    #endif
}

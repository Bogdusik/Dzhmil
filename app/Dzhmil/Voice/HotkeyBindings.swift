import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk", initial: .init(.space, modifiers: [.option]))
}

@MainActor
enum HotkeyBindings {
    static func install(onDown: @escaping @MainActor () -> Void, onUp: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { onDown() }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { onUp() }
    }
}

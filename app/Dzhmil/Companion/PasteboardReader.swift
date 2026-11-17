import AppKit
import DzhmilCore

struct PasteboardReader: ClipboardReader {
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    func read() async -> ClipboardContent {
        await MainActor.run {
            let board = NSPasteboard.general
            let types = board.types ?? []
            if types.contains(Self.concealed) { return .concealed }
            if types.isEmpty { return .empty }
            if let text = board.string(forType: .string) { return .text(text) }
            return .notText
        }
    }
}

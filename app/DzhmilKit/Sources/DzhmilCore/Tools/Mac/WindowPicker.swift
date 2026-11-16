import CoreGraphics

public enum WindowPicker {
    public struct Window: Equatable, Sendable {
        public var id: UInt32
        public var pid: Int32
        public var layer: Int
        public var frame: CGRect
        public init(id: UInt32, pid: Int32, layer: Int, frame: CGRect) {
            self.id = id; self.pid = pid; self.layer = layer; self.frame = frame
        }
    }

    public struct Pick: Equatable, Sendable {
        public var frontID: UInt32
        public var ids: [UInt32]
        public var rect: CGRect
    }

    static let sheetTopTolerance: CGFloat = 60

    public static func pick(_ windows: [Window], pid: Int32) -> Pick? {
        let mine = windows.filter { $0.pid == pid && $0.layer == 0 && $0.frame.width > 80 && $0.frame.height > 60 }
        guard let front = mine.first else { return nil }
        var rect = front.frame
        var ids = [front.id]
        for parent in mine.dropFirst() where isSheet(front.frame, of: parent.frame) {
            rect = rect.union(parent.frame)
            ids.append(parent.id)
        }
        return Pick(frontID: front.id, ids: ids, rect: rect)
    }

    private static func isSheet(_ child: CGRect, of parent: CGRect) -> Bool {
        child.minX >= parent.minX && child.maxX <= parent.maxX && abs(child.minY - parent.minY) <= sheetTopTolerance
    }
}

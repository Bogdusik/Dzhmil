import Foundation

public actor TimerStore {
    private var timers: [(label: String, fireAt: Date)] = []

    public init() {}

    public func add(label: String, fireAt: Date) {
        timers.append((label, fireAt))
    }

    public func due(now: Date) -> [String] {
        let ready = timers.filter { $0.fireAt <= now }
        timers.removeAll { $0.fireAt <= now }
        return ready.map(\.label)
    }

    public var isEmpty: Bool { timers.isEmpty }
}

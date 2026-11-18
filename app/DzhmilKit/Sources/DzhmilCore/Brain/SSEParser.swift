public struct SSEEvent: Equatable, Sendable {
    public var event: String?
    public var data: String

    public init(event: String?, data: String) {
        self.event = event
        self.data = data
    }
}

public struct SSEParser: Sendable {
    private var buffer = ""
    private var event: String?
    private var dataLines: [String] = []

    public init() {}

    public mutating func feed(_ chunk: String) -> [SSEEvent] {
        buffer += chunk.replacingOccurrences(of: "\r\n", with: "\n")
        var out: [SSEEvent] = []
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let e = process(line) { out.append(e) }
        }
        return out
    }

    public mutating func finish() -> [SSEEvent] {
        var out: [SSEEvent] = []
        if !buffer.isEmpty {
            let line = buffer
            buffer = ""
            if let e = process(line) { out.append(e) }
        }
        if let e = dispatch() { out.append(e) }
        return out
    }

    private mutating func process(_ line: String) -> SSEEvent? {
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event": event = String(value)
        case "data": dataLines.append(String(value))
        default: break
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            event = nil
            dataLines = []
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: event, data: dataLines.joined(separator: "\n"))
    }
}

import os

public enum Log {
    public static let subsystem = "com.bogdusik.dzhmil"
    public static let conversation = Logger(subsystem: subsystem, category: "conversation")
    public static let tools = Logger(subsystem: subsystem, category: "tools")
    public static let app = Logger(subsystem: subsystem, category: "app")
}

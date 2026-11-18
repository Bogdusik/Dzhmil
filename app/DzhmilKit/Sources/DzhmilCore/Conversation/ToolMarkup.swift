import Foundation

public enum ToolMarkup {
    static let pattern = #"<\s*/?\s*(?:antml:)?(?:invoke|parameter|function_calls)\b"#

    public static func contains(_ text: String) -> Bool {
        start(in: text) != nil
    }

    public static func strip(_ text: String) -> String {
        guard let start = start(in: text) else { return text }
        return text[..<start].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func start(in text: String) -> String.Index? {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive])?.lowerBound
    }
}

import Testing
@testable import DzhmilCore

@Suite struct ToolMarkupTests {
    @Test func findsToolCallsWrittenAsText() {
        #expect(ToolMarkup.contains("Sure! <invoke name=\"mute\">"))
        #expect(ToolMarkup.contains("<parameter name=\"minutes\">60"))
        #expect(ToolMarkup.contains("<function_calls>"))
        #expect(ToolMarkup.contains("</invoke>"))
    }

    @Test func ignoresOrdinaryText() {
        #expect(!ToolMarkup.contains("I love FPV drones <3"))
        #expect(!ToolMarkup.contains("Invoke the shortcut, then set the parameter."))
    }

    @Test func keepsTextBeforeMarkup() {
        #expect(ToolMarkup.strip("Sure! <invoke name=\"mute\">x") == "Sure!")
        #expect(ToolMarkup.strip("All good.") == "All good.")
    }
}

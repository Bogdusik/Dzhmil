import Foundation
import Testing
@testable import DzhmilCore

@Suite struct JSONValueTests {
    @Test func roundTripsNestedObject() throws {
        let raw = #"{"a":[1,true,null,"x"],"b":{"c":2.5}}"#
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
        #expect(try v.encodedString() == raw)
    }

    @Test func integralNumbersEncodeWithoutFraction() throws {
        #expect(try JSONValue.number(16000).encodedString() == "16000")
    }

    @Test func keysAreSorted() throws {
        #expect(try JSONValue.object(["b": .null, "a": .null]).encodedString() == #"{"a":null,"b":null}"#)
    }

    @Test func accessors() {
        let v = JSONValue.object(["s": .string("x"), "n": .number(3)])
        #expect(v["s"]?.stringValue == "x")
        #expect(v["n"]?.intValue == 3)
        #expect(v["missing"] == nil)
    }

    @Test func intValueRejectsWhatIntCannotHold() {
        #expect(JSONValue.number(1e20).intValue == nil)
        #expect(JSONValue.number(-1e300).intValue == nil)
        #expect(JSONValue.number(.infinity).intValue == nil)
        #expect(JSONValue.number(2.5).intValue == nil)
        #expect(JSONValue.number(-7).intValue == -7)
    }
}

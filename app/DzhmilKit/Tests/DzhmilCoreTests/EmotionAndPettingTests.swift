import CoreGraphics
import Foundation
import Testing
@testable import DzhmilCore

@Suite struct EmotionFilterTests {
    func run(_ deltas: [String]) -> [EmotionPiece] {
        var f = EmotionFilter()
        var out: [EmotionPiece] = []
        for d in deltas { out += f.feed(d) }
        out += f.flush()
        var merged: [EmotionPiece] = []
        for piece in out {
            if case .text(let t) = piece, case .text(let prev)? = merged.last {
                merged[merged.count - 1] = .text(prev + t)
            } else {
                merged.append(piece)
            }
        }
        return merged
    }

    @Test func plainTextPassesThrough() {
        #expect(run(["Hi, ", "how are you?"]) == [.text("Hi, how are you?")])
    }

    @Test func tagBecomesEmotionAndEatsOneSpace() {
        #expect(run(["<happy> Yay!"]) == [.emotion(.happy), .text("Yay!")])
    }

    @Test func tagSplitAcrossDeltas() {
        #expect(run(["Well ", "<sur", "pri", "sed>", "Wow!"]) == [.text("Well "), .emotion(.surprised), .text("Wow!")])
    }

    @Test(arguments: Emotion.allCases)
    func everyEmotionParses(_ e: Emotion) {
        #expect(run(["<\(e.rawValue)>Yes."]) == [.emotion(e), .text("Yes.")])
    }

    @Test func unknownTagIsDropped() {
        #expect(run(["<wink>Fine."]) == [.text("Fine.")])
    }

    @Test func comparisonsStayText() {
        #expect(run(["If a < b, then", " 3<5 and x<10."]) == [.text("If a < b, then 3<5 and x<10.")])
    }

    @Test func unfinishedTagIsFlushedAsText() {
        #expect(run(["The end <hap"]) == [.text("The end <hap")])
    }

    @Test func thinkingModeMarkupIsDroppedWithItsContent() {
        #expect(run(["<thinking_mode>auto</thinking_mode> Hello there."]) == [.text("Hello there.")])
    }

    @Test func thinkingModeMarkupSplitAcrossDeltas() {
        #expect(run(["<thinking_", "mode>au", "to</thinking", "_mode>Hi."]) == [.text("Hi.")])
    }

    @Test func unclosedThinkingModeKeepsTheText() {
        let reply = "auto and then a long answer that goes on well past the limit of the markup."
        #expect(run(["<thinking_mode>" + reply]) == [.text(reply)])
    }

    @Test func unknownTagsWithUnderscoresAndStrayClosingTagsAreDropped() {
        #expect(run(["<foo_bar>Text"]) == [.text("Text")])
        #expect(run(["</foo>Text"]) == [.text("Text")])
    }

    @Test func stripRemovesMarkup() {
        #expect(EmotionFilter.strip("<thinking_mode>auto</thinking_mode> <happy>Good morning!") == "Good morning!")
    }

    @Test func longAngleTextStaysText() {
        #expect(run(["<abcdefghijklmnopqrstuvwxyz>"]) == [.text("<abcdefghijklmnopqrstuvwxyz>")])
    }
}

@Suite struct PetDetectorTests {
    func stroke(_ d: inout PetDetector, from t0: Double, seconds: Double, amplitude: Double = 20, hz: Double = 2,
                over: Bool = true, button: Bool = false) -> [PetDetector.Event] {
        var events: [PetDetector.Event] = []
        var t = t0
        while t < t0 + seconds {
            let x = 500 + amplitude * sin(2 * Double.pi * hz * (t - t0))
            events += d.update(x: x, time: t, overDrone: over, buttonDown: button)
            t += 0.05
        }
        return events
    }

    @Test func backAndForthStartsPetting() {
        var d = PetDetector()
        let events = stroke(&d, from: 0, seconds: 1.2)
        #expect(events == [.started])
        #expect(d.isPetting)
    }

    @Test func jitterIsNotPetting() {
        var d = PetDetector()
        #expect(stroke(&d, from: 0, seconds: 3, amplitude: 1.5).isEmpty)
        #expect(!d.isPetting)
    }

    @Test func slowSweepsAreNotPetting() {
        var d = PetDetector()
        #expect(stroke(&d, from: 0, seconds: 4, hz: 0.3).isEmpty)
    }

    @Test func holdingAButtonIsADragNotPetting() {
        var d = PetDetector()
        #expect(stroke(&d, from: 0, seconds: 2, button: true).isEmpty)
    }

    @Test func leavingTheDroneEnds() {
        var d = PetDetector()
        _ = stroke(&d, from: 0, seconds: 1.2)
        #expect(d.update(x: 900, time: 1.25, overDrone: false, buttonDown: false) == [.ended])
        #expect(!d.isPetting)
    }

    @Test func stillnessEnds() {
        var d = PetDetector()
        _ = stroke(&d, from: 0, seconds: 1.2)
        #expect(d.update(x: 500, time: 1.3, overDrone: true, buttonDown: false) == [])
        #expect(d.update(x: 500, time: 1.3, overDrone: true, buttonDown: false) == [])
        #expect(d.update(x: 500, time: 2.3, overDrone: true, buttonDown: false) == [.ended])
    }

    @Test func heartsEveryThreeSeconds() {
        var d = PetDetector()
        let events = stroke(&d, from: 0, seconds: 7.5)
        #expect(events == [.started, .heart, .heart])
    }
}

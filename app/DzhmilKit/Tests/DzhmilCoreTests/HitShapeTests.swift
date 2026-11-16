import CoreGraphics
import Testing
@testable import DzhmilCore

@Suite struct HitShapeTests {
    let shape = HitShape(droneRect: CGRect(x: 100, y: 0, width: 140, height: 105), bubbleRect: CGRect(x: 40, y: 150, width: 260, height: 120))

    @Test func centerOfDroneHits() {
        #expect(shape.contains(CGPoint(x: 170, y: 52)))
    }

    @Test func transparentCornersPassThrough() {
        #expect(!shape.contains(CGPoint(x: 101, y: 1)))
        #expect(!shape.contains(CGPoint(x: 239, y: 104)))
        #expect(!shape.contains(CGPoint(x: 5, y: 5)))
    }

    @Test func bubbleHits() {
        #expect(shape.contains(CGPoint(x: 60, y: 200)))
        #expect(!HitShape(droneRect: shape.droneRect, bubbleRect: nil).contains(CGPoint(x: 60, y: 200)))
    }

    @Test func fullscreenOnNotchedDisplay() {
        let screen = FullscreenDetector.Screen(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), topInset: 32)
        #expect(FullscreenDetector.matches(CGRect(x: 0, y: 0, width: 1728, height: 1085), screens: [screen]))
        #expect(FullscreenDetector.matches(CGRect(x: 0, y: 0, width: 1728, height: 1117), screens: [screen]))
        #expect(!FullscreenDetector.matches(CGRect(x: 0, y: 0, width: 1728, height: 1084), screens: [screen]))
        #expect(!FullscreenDetector.matches(CGRect(x: 100, y: 0, width: 900, height: 700), screens: [screen]))
    }

    @Test func cgToAppKitFlipsY() {
        #expect(Coordinates.cgToAppKit(CGRect(x: 0, y: 0, width: 100, height: 50), primaryScreenHeight: 1000) == CGRect(x: 0, y: 950, width: 100, height: 50))
    }
}

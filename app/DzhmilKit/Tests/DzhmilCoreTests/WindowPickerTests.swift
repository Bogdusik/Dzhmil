import CoreGraphics
import Testing
@testable import DzhmilCore

@Suite struct WindowPickerTests {
    let app: Int32 = 42

    func w(_ id: UInt32, _ pid: Int32, _ rect: CGRect, layer: Int = 0) -> WindowPicker.Window {
        WindowPicker.Window(id: id, pid: pid, layer: layer, frame: rect)
    }

    @Test func picksFrontmostNotLargest() {
        let windows = [w(1, app, CGRect(x: 600, y: 100, width: 400, height: 300)), w(2, app, CGRect(x: 0, y: 0, width: 1400, height: 900))]
        let pick = WindowPicker.pick(windows, pid: app)
        #expect(pick?.frontID == 1)
        #expect(pick?.rect == CGRect(x: 600, y: 100, width: 400, height: 300))
    }

    @Test func includesSheetOverFrontWindow() {
        let sheet = w(5, app, CGRect(x: 400, y: 60, width: 500, height: 200))
        let doc = w(6, app, CGRect(x: 200, y: 40, width: 1000, height: 700))
        let pick = WindowPicker.pick([sheet, doc], pid: app)
        #expect(pick?.frontID == 5)
        #expect(pick?.rect == CGRect(x: 200, y: 40, width: 1000, height: 700))
        #expect(pick?.ids == [5, 6])
    }

    @Test func ignoresOtherAppsTinyAndOverlayWindows() {
        let windows = [w(1, 7, CGRect(x: 0, y: 0, width: 800, height: 600)),
                       w(2, app, CGRect(x: 10, y: 10, width: 30, height: 20)),
                       w(3, app, CGRect(x: 0, y: 0, width: 500, height: 400), layer: 25),
                       w(4, app, CGRect(x: 900, y: 500, width: 600, height: 400)),
                       w(9, app, CGRect(x: 0, y: 0, width: 300, height: 200))]
        let pick = WindowPicker.pick(windows, pid: app)
        #expect(pick?.frontID == 4)
        #expect(pick?.ids == [4])
    }

    @Test func noWindowsIsNil() {
        #expect(WindowPicker.pick([w(1, 7, CGRect(x: 0, y: 0, width: 800, height: 600))], pid: app) == nil)
    }
}

#if DEBUG
import Foundation
import Darwin
import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import DzhmilCore

enum DebugTools {
    static func transcribeTest(path: String) async {
        let transcriber = Transcriber()
        do {
            var t = Date()
            try await transcriber.prepare()
            print("prepare: \(String(format: "%.1f", Date().timeIntervalSince(t))) s")
            let samples = try Transcriber.loadAudio(path: path)
            print("audio: \(String(format: "%.1f", Double(samples.count) / 16_000)) s")
            for run in 1...2 {
                t = Date()
                let text = try await transcriber.transcribe(samples)
                print("run \(run): \(String(format: "%.2f", Date().timeIntervalSince(t))) s → \(text) → filtered: \(TranscriptFilter.clean(text) ?? "nil")")
            }
            print("memory: \(footprintMB()) MB")
        } catch {
            print("error: \(error)")
        }
    }

    static func screenshot(to url: URL) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { return }
            let config = SCStreamConfiguration()
            config.width = display.width * 2
            config.height = display.height * 2
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        } catch {
            print("screenshot failed: \(error)")
        }
    }

    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return r == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}
#endif

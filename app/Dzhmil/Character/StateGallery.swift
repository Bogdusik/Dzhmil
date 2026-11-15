#if DEBUG
import SwiftUI
import AppKit
import DzhmilCore

struct StateGalleryView: View {
    @State private var state: DroneState = .hover
    @State private var bank: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            DroneView(state: state, bankDegrees: bank)
                .frame(width: 320, height: 220)
                .background(LinearGradient(colors: [Color(hex: 0xCFE7F2), Color(hex: 0xE9F4EC)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(DroneState.allCases, id: \.self) { s in
                    Button(s.rawValue) { state = s }
                        .buttonStyle(.bordered)
                        .tint(s == state ? .accentColor : .gray)
                }
            }
            HStack {
                Text("Крен")
                Slider(value: $bank, in: -14...14)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

@MainActor
enum StateGallery {
    static func renderAll(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for s in DroneState.allCases {
            let view = DroneView(state: s, bankDegrees: s == .flying ? 10 : 0)
                .frame(width: 200, height: 160)
                .background(Color(hex: 0xE9F4EC))
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appendingPathComponent("\(s.rawValue).png"))
            }
        }
    }

    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: StateGalleryView()))
            w.title = "Галерея состояний"
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
#endif

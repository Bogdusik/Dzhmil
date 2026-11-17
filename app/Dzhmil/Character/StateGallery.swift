#if DEBUG
import SwiftUI
import AppKit
import DzhmilCore

struct StateGalleryView: View {
    @State private var state: DroneState = .hover
    @State private var bank: Double = 0
    @State private var bubble: Bubble?
    @State private var speaker = Speaker()
    @State private var gesture: GestureRequest?
    @State private var eyeX: Double = 0
    @State private var eyeY: Double = 0

    static let gestures: [(String, DroneGesture)] = [
        ("Look around", .idle(.lookAround)), ("Tilt", .idle(.tilt)), ("Hop", .idle(.hop)), ("Yawn", .idle(.yawn)),
        ("Barrel roll", .idle(.barrelRoll)), ("Wiggle", .wiggle), ("Startle", .startle), ("Flash", .cameraFlash), ("Steady", .steady(fromLeft: true)),
        ("happy", .emotion(.happy)), ("laugh", .emotion(.laugh)), ("surprised", .emotion(.surprised)),
        ("thinking", .emotion(.thinking)), ("sad", .emotion(.sad)), ("Heart", .heart),
    ]

    static let samples: [(String, Bubble)] = [
        ("Text", .text("Hi! How's it going? Battery at 87%, all good.")),
        ("Question", .question("You've been at the computer for two hours. Time for a break?")),
        ("Confirm", .confirm(ConfirmationRequest(question: "Run this command in Terminal?", detail: "ls -la ~/Desktop/PROJECTS | head -20"))),
        ("Input", .input),
        ("Key", .onboardingKey(Onboarding.greeting)),
    ]

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                if let bubble { BubbleView(bubble: bubble, onAnswer: { _ in self.bubble = nil }, onSubmit: { _ in self.bubble = nil }, onReply: { self.bubble = nil }, onLater: { self.bubble = nil }, onCancel: { self.bubble = nil }) }
                DroneView(state: state, bankDegrees: bank, gesture: gesture, eyeOffset: CGVector(dx: eyeX, dy: eyeY))
            }
            .frame(width: 340, height: 320, alignment: .bottom)
            .background(LinearGradient(colors: [Color(hex: 0xCFE7F2), Color(hex: 0xE9F4EC)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(DroneState.allCases, id: \.self) { s in
                    Button(s.rawValue) { state = s }
                        .buttonStyle(.bordered)
                        .tint(s == state ? .accentColor : .gray)
                }
            }
            HStack {
                Text("Bank")
                Slider(value: $bank, in: -14...14)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(Self.gestures, id: \.0) { item in
                    Button(item.0) { gesture = GestureRequest(id: (gesture?.id ?? 0) + 1, gesture: item.1) }
                }
            }
            .buttonStyle(.bordered)
            HStack {
                Text("Eyes")
                Slider(value: $eyeX, in: -3...3)
                Slider(value: $eyeY, in: -2...2)
            }
            HStack {
                ForEach(Self.samples, id: \.0) { item in
                    Button(item.0) { bubble = item.1 }
                }
                Button("No bubble") { bubble = nil }
            }
            .buttonStyle(.bordered)
            HStack {
                Button("Speak") { speaker.enqueue("Hi! I'm Dzhmil, your little drone. How are you?") }
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 560)
    }
}

@MainActor
enum StateGallery {
    static func renderAll(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for s in DroneState.allCases {
            let view = DroneLayerView(width: 200)
            view.apply(state: s)
            view.setBank(s == .flying ? 10 : 0)
            if let img = view.renderImage(), let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appendingPathComponent("\(s.rawValue).png"))
            }
        }
        let looking = DroneLayerView(width: 200)
        looking.apply(state: .hover)
        looking.setEyeOffset(CGVector(dx: 3, dy: 2))
        if let img = looking.renderImage(), let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("eyes-up-right.png"))
        }
        let icon = MenuBarController.icon()
        if let tiff = icon.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("menu-icon.png"))
        }
        for (i, item) in StateGalleryView.samples.enumerated() {
            let r = ImageRenderer(content: BubbleView(bubble: item.1).padding(12).background(Color(hex: 0xE9F4EC)))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appendingPathComponent("bubble-\(i).png"))
            }
        }
    }

    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: StateGalleryView()))
            w.title = "State Gallery"
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
#endif

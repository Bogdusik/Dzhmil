import SwiftUI
import DzhmilCore

enum DronePalette {
    static let body = Color(hex: 0x00D4AA)
    static let belly = Color(hex: 0x009C82)
    static let shine = Color(hex: 0x7DF3D8)
    static let frame = Color(hex: 0x20343A)
    static let visor = Color(hex: 0x0A1B20)
    static let eye = Color(hex: 0x8CFFE4)
    static let uaBlue = Color(hex: 0x2B6FE0)
    static let uaYellow = Color(hex: 0xFFD23F)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

struct DroneView: View {
    static let width: CGFloat = 140
    static let canvas = CGSize(width: 240, height: 180)
    static var height: CGFloat { width * canvas.height / canvas.width }

    let state: DroneState
    let bankDegrees: Double

    @State private var bobUp = false
    @State private var blink = false
    @State private var flipCount = 0
    @State private var shakeCount = 0

    private var face: DroneFace { DroneFace.face(for: state) }
    private var scale: CGFloat { Self.width / Self.canvas.width }

    var body: some View {
        DroneDrawing(face: face)
            .frame(width: Self.canvas.width, height: Self.canvas.height)
            .overlay { if face.ring { ListeningRing() } }
            .overlay(alignment: .topTrailing) { if face.zzz { Snore() } }
            .environment(\.droneBlink, blink)
            .keyframeAnimator(initialValue: FlipPose(), trigger: flipCount) { content, pose in
                content
                    .rotationEffect(.degrees(pose.angle), anchor: UnitPoint(x: 0.5, y: 0.55))
                    .offset(y: pose.lift)
            } keyframes: { _ in
                KeyframeTrack(\.angle) {
                    CubicKeyframe(200, duration: 0.43)
                    CubicKeyframe(360, duration: 0.52)
                    LinearKeyframe(0, duration: 0.001)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-26, duration: 0.43)
                    CubicKeyframe(0, duration: 0.52)
                }
            }
            .keyframeAnimator(initialValue: 0.0, trigger: shakeCount) { content, angle in
                content.rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.5, y: 0.55))
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-9, duration: 0.12)
                    CubicKeyframe(9, duration: 0.16)
                    CubicKeyframe(-6, duration: 0.14)
                    CubicKeyframe(0, duration: 0.12)
                }
            }
            .rotationEffect(.degrees(bankDegrees), anchor: UnitPoint(x: 0.5, y: 0.55))
            .offset(y: face.propellersSpinning ? (bobUp ? -5 : 5) : 0)
            .animation(face.propellersSpinning ? .easeInOut(duration: 1.3).repeatForever(autoreverses: true) : .easeOut(duration: 0.4), value: bobUp)
            .scaleEffect(scale)
            .frame(width: Self.width, height: Self.height)
            .onAppear { bobUp = true }
            .onChange(of: state) { _, new in
                if new == .celebrating { flipCount += 1 }
                if new == .error { shakeCount += 1 }
                bobUp = face.propellersSpinning
            }
            .task(id: state == .sleeping) {
                guard state != .sleeping else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Double.random(in: 3.2...5.2)))
                    withAnimation(.easeIn(duration: 0.07)) { blink = true }
                    try? await Task.sleep(for: .milliseconds(110))
                    withAnimation(.easeOut(duration: 0.09)) { blink = false }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Джміль")
    }
}

private struct FlipPose {
    var angle: Double = 0
    var lift: Double = 0
}

private struct BlinkKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var droneBlink: Bool {
        get { self[BlinkKey.self] }
        set { self[BlinkKey.self] = newValue }
    }
}

private struct DroneDrawing: View {
    let face: DroneFace

    var body: some View {
        ZStack(alignment: .topLeading) {
            Stroke(points: [(96, 82), (54, 56)], width: 8)
            Stroke(points: [(144, 82), (186, 56)], width: 8)
            Box(x: 47, y: 46, w: 14, h: 13, r: 3, color: DronePalette.frame)
            Box(x: 179, y: 46, w: 14, h: 13, r: 3, color: DronePalette.frame)
            Propeller(center: CGPoint(x: 54, y: 44), radius: 30, discHeight: 18, bladeThickness: 8, spinning: face.propellersSpinning)
            Propeller(center: CGPoint(x: 186, y: 44), radius: 30, discHeight: 18, bladeThickness: 8, spinning: face.propellersSpinning)

            Stroke(points: [(150, 66), (166, 40)], width: 3)
            AntennaLED(mode: face.led)

            Stroke(points: [(102, 136), (96, 150)], width: 4)
            Stroke(points: [(138, 136), (144, 150)], width: 4)

            Box(x: 78, y: 66, w: 84, h: 62, r: 26, color: DronePalette.belly)
            Box(x: 78, y: 60, w: 84, h: 62, r: 26, color: DronePalette.body)
            Box(x: 96, y: 65, w: 30, h: 5, r: 2.5, color: DronePalette.shine.opacity(0.7))
            Box(x: 87, y: 76, w: 66, h: 34, r: 15, color: DronePalette.visor)
            Box(x: 94, y: 123, w: 52, h: 17, r: 5, color: DronePalette.frame)
            Box(x: 111, y: 123, w: 18, h: 8.5, r: 0, color: DronePalette.uaBlue)
            Box(x: 111, y: 131.5, w: 18, h: 8.5, r: 0, color: DronePalette.uaYellow)

            DroneEyes(kind: face.eyes)
            if face.mouthTalking { Mouth() }

            Stroke(points: [(92, 108), (40, 122)], width: 10)
            Stroke(points: [(148, 108), (200, 122)], width: 10)
            Box(x: 31, y: 107, w: 18, h: 17, r: 4, color: DronePalette.frame)
            Box(x: 191, y: 107, w: 18, h: 17, r: 4, color: DronePalette.frame)
            Propeller(center: CGPoint(x: 40, y: 104), radius: 38, discHeight: 22, bladeThickness: 10, spinning: face.propellersSpinning)
            Propeller(center: CGPoint(x: 200, y: 104), radius: 38, discHeight: 22, bladeThickness: 10, spinning: face.propellersSpinning)
        }
        .frame(width: DroneView.canvas.width, height: DroneView.canvas.height, alignment: .topLeading)
    }
}

private struct Stroke: View {
    let points: [(CGFloat, CGFloat)]
    let width: CGFloat
    var color: Color = DronePalette.frame

    var body: some View {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: CGPoint(x: first.0, y: first.1))
            for pt in points.dropFirst() { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

private struct Box: View {
    let x, y, w, h, r: CGFloat
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: r, style: .continuous)
            .fill(color)
            .frame(width: w, height: h)
            .offset(x: x, y: y)
    }
}

private struct Propeller: View {
    let center: CGPoint
    let radius: CGFloat
    let discHeight: CGFloat
    let bladeThickness: CGFloat
    let spinning: Bool

    @State private var spin = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(DronePalette.frame.opacity(spinning ? 0.16 : 0))
                .frame(width: radius * 2, height: discHeight)
            Capsule()
                .fill(DronePalette.frame)
                .frame(width: radius * 2, height: bladeThickness)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(spin ? .linear(duration: 0.24).repeatForever(autoreverses: false) : .easeOut(duration: 0.8), value: spin)
                .scaleEffect(x: 1, y: 0.3)
        }
        .frame(width: radius * 2, height: discHeight)
        .position(center)
        .onAppear { spin = spinning }
        .onChange(of: spinning) { _, new in spin = new }
    }
}

private struct AntennaLED: View {
    let mode: DroneFace.LED
    @State private var on = true

    var body: some View {
        Circle()
            .fill(DronePalette.uaYellow)
            .frame(width: 9, height: 9)
            .opacity(mode == .dim ? 0.35 : (on ? 1 : 0.25))
            .position(x: 166, y: 39)
            .animation(mode == .dim ? .default : .easeInOut(duration: mode == .fast ? 0.25 : 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = false }
            .onChange(of: mode) { _, _ in on.toggle() }
    }
}

private struct DroneEyes: View {
    let kind: DroneFace.Eyes
    @Environment(\.droneBlink) private var blink
    @State private var dart = false

    var body: some View {
        switch kind {
        case .open, .wide, .darting:
            HStack(spacing: 18) {
                eye
                eye
            }
            .scaleEffect(kind == .wide ? 1.25 : 1)
            .scaleEffect(x: 1, y: blink ? 0.1 : 1)
            .offset(x: kind == .darting ? (dart ? 3 : -3) : 0)
            .animation(kind == .darting ? .easeInOut(duration: 0.35).repeatForever(autoreverses: true) : .default, value: dart)
            .position(x: 120, y: 91)
            .onAppear { dart = kind == .darting }
            .onChange(of: kind) { _, new in dart = new == .darting }
        case .happy:
            Stroke(points: [(100, 95), (106, 87), (112, 95)], width: 3.2, color: DronePalette.eye)
            Stroke(points: [(128, 95), (134, 87), (140, 95)], width: 3.2, color: DronePalette.eye)
        case .sad:
            Stroke(points: [(100, 90), (112, 85)], width: 3, color: DronePalette.eye)
            Stroke(points: [(128, 85), (140, 90)], width: 3, color: DronePalette.eye)
            HStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 4).fill(DronePalette.eye).frame(width: 10, height: 8)
                RoundedRectangle(cornerRadius: 4).fill(DronePalette.eye).frame(width: 10, height: 8)
            }
            .position(x: 120, y: 98)
        case .sleepy:
            SleepyEye(x: 100)
            SleepyEye(x: 128)
        }
    }

    private var eye: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(DronePalette.eye)
            .frame(width: 10, height: 14)
    }
}

private struct SleepyEye: View {
    let x: CGFloat

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: x, y: 90))
            p.addQuadCurve(to: CGPoint(x: x + 12, y: 90), control: CGPoint(x: x + 6, y: 96))
        }
        .stroke(DronePalette.eye, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
    }
}

private struct Mouth: View {
    @State private var talk = false

    var body: some View {
        HStack(spacing: 1.7) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(DronePalette.eye)
                    .frame(width: 3.5, height: 4)
                    .scaleEffect(x: 1, y: talk ? 1.5 : 0.4)
                    .animation(.easeInOut(duration: 0.25).repeatForever(autoreverses: true).delay(Double(i) * 0.12), value: talk)
            }
        }
        .position(x: 120, y: 103)
        .onAppear { talk = true }
    }
}

private struct ListeningRing: View {
    @State private var grow = false

    var body: some View {
        Circle()
            .stroke(DronePalette.body, lineWidth: 2)
            .frame(width: 168, height: 168)
            .scaleEffect(grow ? 1.5 : 0.7)
            .opacity(grow ? 0 : 0.9)
            .position(x: 120, y: 93.6)
            .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: grow)
            .onAppear { grow = true }
            .allowsHitTesting(false)
    }
}

private struct Snore: View {
    @State private var drift = false

    var body: some View {
        Text("z z z")
            .font(.system(size: 22, weight: .semibold, design: .monospaced))
            .foregroundStyle(DronePalette.frame.opacity(0.75))
            .offset(x: drift ? 10 : -10, y: drift ? -30 : 0)
            .opacity(drift ? 0 : 1)
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false), value: drift)
            .onAppear { drift = true }
            .allowsHitTesting(false)
    }
}

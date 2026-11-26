import Foundation

public struct DroneColorPreset: Identifiable, Equatable, Sendable {
    public let name: String
    public let hex: UInt32
    public var id: UInt32 { hex }

    public static let all = [
        DroneColorPreset(name: "turquoise", hex: DronePaint.turquoise),
        DroneColorPreset(name: "yellow", hex: 0xFFC21A),
        DroneColorPreset(name: "coral", hex: 0xFF6B5E),
        DroneColorPreset(name: "pink", hex: 0xFF5FA2),
        DroneColorPreset(name: "violet", hex: 0x8B6CFF),
        DroneColorPreset(name: "blue", hex: 0x2FA8FF),
        DroneColorPreset(name: "lime", hex: 0x7ED321),
        DroneColorPreset(name: "graphite", hex: 0x6B7A86),
    ]

    public static let parts = [
        DroneColorPreset(name: "dark", hex: DronePaint.frame),
        DroneColorPreset(name: "white", hex: 0xFFFFFF),
    ] + all.filter { $0.name != "graphite" }
}

public struct DroneLook: Equatable, Sendable {
    public var body, arms, propellers: UInt32

    public init(body: UInt32 = DronePaint.turquoise, arms: UInt32 = DronePaint.frame, propellers: UInt32 = DronePaint.frame) {
        self.body = body
        self.arms = arms
        self.propellers = propellers
    }
}

public struct DronePaint: Equatable, Sendable {
    public static let turquoise: UInt32 = 0x00D4AA
    public static let frame: UInt32 = 0x20343A
    static let visor: UInt32 = 0x0A1B20

    public let body, belly, shine, eye, button, accent: UInt32

    public init(_ base: UInt32) {
        body = base
        guard base != Self.turquoise else {
            (belly, shine, eye, button, accent) = (0x009C82, 0x7DF3D8, 0x8CFFE4, 0x008F74, base)
            return
        }
        belly = Self.mix(base, 0x000000, 0.27)
        shine = Self.mix(base, 0xFFFFFF, 0.5)
        eye = Self.adjust(Self.mix(base, 0xFFFFFF, 0.55), toward: 0xFFFFFF, until: 7, against: Self.visor)
        button = Self.adjust(Self.mix(base, 0x000000, 0.3), toward: 0x000000, until: 4, against: 0xFFFFFF)
        accent = Self.adjust(base, toward: 0xFFFFFF, until: 3, against: Self.visor)
    }

    public static func name(of hex: UInt32) -> String {
        if let preset = DroneColorPreset.all.first(where: { $0.hex == hex }) { return preset.name }
        let (r, g, b) = components(hex)
        let high = max(r, g, b), spread = high - min(r, g, b)
        if high < 0.2 { return "black" }
        if spread / high < 0.15 { return high > 0.85 ? "white" : "grey" }
        let sector = high == r ? (g - b) / spread : high == g ? (b - r) / spread + 2 : (r - g) / spread + 4
        let hue = (sector * 60 + 360).truncatingRemainder(dividingBy: 360)
        switch hue {
        case 15..<45: return "orange"
        case 45..<70: return "yellow"
        case 70..<160: return "green"
        case 160..<195: return "turquoise"
        case 195..<255: return "blue"
        case 255..<290: return "purple"
        case 290..<345: return "pink"
        default: return "red"
        }
    }

    private static func components(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private static func mix(_ hex: UInt32, _ other: UInt32, _ amount: Double) -> UInt32 {
        let a = components(hex), b = components(other)
        func channel(_ x: Double, _ y: Double) -> UInt32 { UInt32(((x + (y - x) * amount) * 255).rounded()) }
        return channel(a.0, b.0) << 16 | channel(a.1, b.1) << 8 | channel(a.2, b.2)
    }

    private static func luminance(_ hex: UInt32) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = components(hex)
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static func adjust(_ hex: UInt32, toward target: UInt32, until ratio: Double, against other: UInt32) -> UInt32 {
        var color = hex
        let reference = luminance(other)
        for _ in 0..<40 {
            let own = luminance(color)
            if (max(own, reference) + 0.05) / (min(own, reference) + 0.05) >= ratio { break }
            color = mix(color, target, 0.12)
        }
        return color
    }
}

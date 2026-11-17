public enum DroneState: String, CaseIterable, Sendable {
    case hover, flying, listening, thinking, speaking, confirming, celebrating, error, sleeping
}

public struct DroneFace: Equatable, Sendable {
    public enum Eyes: Sendable { case open, wide, darting, happy, sad, sleepy }
    public enum LED: Sendable { case slow, fast, dim }

    public var eyes: Eyes
    public var mouthTalking: Bool
    public var propellersSpinning: Bool
    public var led: LED
    public var ring: Bool
    public var zzz: Bool

    public init(eyes: Eyes, mouthTalking: Bool, propellersSpinning: Bool, led: LED, ring: Bool, zzz: Bool) {
        self.eyes = eyes
        self.mouthTalking = mouthTalking
        self.propellersSpinning = propellersSpinning
        self.led = led
        self.ring = ring
        self.zzz = zzz
    }

    public static func face(for state: DroneState) -> DroneFace {
        let calm = DroneFace(eyes: .open, mouthTalking: false, propellersSpinning: true, led: .slow, ring: false, zzz: false)
        var f = calm
        switch state {
        case .hover, .flying, .confirming:
            break
        case .listening:
            f.eyes = .wide
            f.ring = true
        case .thinking:
            f.eyes = .darting
            f.led = .fast
        case .speaking:
            f.mouthTalking = true
        case .celebrating:
            f.eyes = .happy
        case .error:
            f.eyes = .sad
        case .sleeping:
            f = DroneFace(eyes: .sleepy, mouthTalking: false, propellersSpinning: false, led: .dim, ring: false, zzz: true)
        }
        return f
    }
}

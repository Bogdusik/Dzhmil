public enum BehaviorEvent: Equatable, Sendable {
    case wanderStarted, arrived
    case pttDown, pttUp, transcriptReady, transcriptEmpty
    case replyStarted, replyFinished(didAct: Bool)
    case confirmationRequested, confirmationResolved
    case failed, animationDone
    case userIdle, userActive
    case quietChanged(Bool), fullscreenChanged(Bool)
}

public enum BehaviorEffect: Equatable, Sendable {
    case startRecording, stopRecording, stopSpeech, cancelConversation, flyToDock, wakeUp
}

public struct BehaviorMachine: Sendable {
    public private(set) var state: DroneState = .hover
    public private(set) var pendingConfirmation = false
    public private(set) var quiet = false
    public private(set) var fullscreen = false

    public init() {}

    public var canWander: Bool {
        state == .hover && !quiet && !fullscreen
    }

    public var canSpeakFirst: Bool {
        [.hover, .flying, .sleeping].contains(state) && !quiet && !fullscreen
    }

    public mutating func handle(_ event: BehaviorEvent) -> [BehaviorEffect] {
        switch event {
        case .pttDown:
            guard state != .listening else { return [] }
            var effects: [BehaviorEffect] = []
            if state == .sleeping { effects.append(.wakeUp) }
            if !pendingConfirmation, state == .speaking || state == .thinking {
                effects += [.stopSpeech, .cancelConversation]
            }
            effects.append(.startRecording)
            state = .listening
            return effects

        case .pttUp:
            guard state == .listening else { return [] }
            state = .thinking
            return [.stopRecording]

        case .transcriptReady:
            return []

        case .transcriptEmpty:
            guard state == .thinking || state == .listening else { return [] }
            state = pendingConfirmation ? .confirming : .hover
            return []

        case .replyStarted:
            if state == .thinking { state = .speaking }
            return []

        case .replyFinished(let didAct):
            guard state == .speaking || state == .thinking else { return [] }
            state = didAct ? .celebrating : .hover
            return []

        case .confirmationRequested:
            guard [.thinking, .speaking, .listening].contains(state) else { return [] }
            pendingConfirmation = true
            state = .confirming
            return []

        case .confirmationResolved:
            guard pendingConfirmation else { return [] }
            pendingConfirmation = false
            if [.confirming, .listening, .thinking].contains(state) { state = .thinking }
            return []

        case .failed:
            pendingConfirmation = false
            state = .error
            return []

        case .animationDone:
            if state == .celebrating || state == .error { state = .hover }
            return []

        case .userIdle:
            guard state == .hover || state == .flying else { return [] }
            state = .sleeping
            return [.flyToDock]

        case .userActive:
            guard state == .sleeping else { return [] }
            state = .hover
            return [.wakeUp]

        case .wanderStarted:
            guard canWander else { return [] }
            state = .flying
            return []

        case .arrived:
            if state == .flying { state = .hover }
            return []

        case .quietChanged(let on):
            quiet = on
            return []

        case .fullscreenChanged(let on):
            fullscreen = on
            return []
        }
    }
}

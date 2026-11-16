import AppKit
import DzhmilCore

@MainActor
final class BubbleConfirmer: ConfirmationProvider {
    private weak var director: DroneDirector?
    private var continuation: CheckedContinuation<Bool, Never>?
    var onShow: (() -> Void)?

    init(director: DroneDirector) {
        self.director = director
    }

    var isWaiting: Bool { continuation != nil }

    func confirm(_ request: ConfirmationRequest) async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                begin(request, c)
            }
        } onCancel: {
            Task { @MainActor in self.resolve(false) }
        }
    }

    private func begin(_ request: ConfirmationRequest, _ c: CheckedContinuation<Bool, Never>) {
        if let old = continuation {
            continuation = nil
            old.resume(returning: false)
        }
        continuation = c
        director?.send(.confirmationRequested)
        director?.model.bubble = .confirm(request)
        NSSound(named: "Tink")?.play()
        onShow?()
    }

    func resolve(_ yes: Bool) {
        guard let c = continuation else { return }
        continuation = nil
        if case .confirm? = director?.model.bubble { director?.model.bubble = nil }
        director?.send(.confirmationResolved)
        c.resume(returning: yes)
    }
}

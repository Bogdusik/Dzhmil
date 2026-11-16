import AppKit
import DzhmilCore

@MainActor
final class BubbleConfirmer: ConfirmationProvider {
    private weak var director: DroneDirector?
    private var gate = ConfirmationGate()
    private var continuation: CheckedContinuation<Bool, Never>?
    var showBubble: ((Bubble?) -> Void)?

    init(director: DroneDirector) {
        self.director = director
    }

    var currentID: Int? { gate.currentID }

    func confirm(_ request: ConfirmationRequest) async -> Bool {
        let id = gate.begin(at: Date())
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                begin(request, id: id, c)
            }
        } onCancel: {
            Task { @MainActor in self.resolve(false, id: id) }
        }
    }

    private func begin(_ request: ConfirmationRequest, id: Int, _ c: CheckedContinuation<Bool, Never>) {
        guard gate.currentID == id else {
            c.resume(returning: false)
            return
        }
        if let old = continuation {
            continuation = nil
            old.resume(returning: false)
        }
        continuation = c
        director?.send(.confirmationRequested)
        showBubble?(.confirm(request))
        NSSound(named: "Tink")?.play()
    }

    func answerFromButton(_ yes: Bool) {
        guard gate.acceptsClick(at: Date()) else { return }
        resolve(yes, id: gate.currentID)
    }

    func resolve(_ yes: Bool, id: Int?) {
        guard gate.resolve(id: id), let c = continuation else { return }
        continuation = nil
        if case .confirm? = director?.model.bubble { showBubble?(nil) }
        director?.send(.confirmationResolved)
        c.resume(returning: yes)
    }
}

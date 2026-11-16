import SwiftUI
import DzhmilCore

enum Bubble: Equatable {
    case text(String)
    case question(String)
    case confirm(ConfirmationRequest)
    case input
    case onboardingKey(String)
}

enum DragPhase { case changed, ended }

@MainActor
@Observable
final class CompanionViewModel {
    var state: DroneState = .hover
    var bankDegrees: Double = 0
    var bubble: Bubble?
    var bubbleRect: CGRect?

    @ObservationIgnored var onDrag: ((DragPhase) -> Void)?
    @ObservationIgnored var onDoubleClick: (() -> Void)?
    @ObservationIgnored var bubbleContent: ((Bubble) -> AnyView)?
}

private struct BubbleFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct CompanionView: View {
    let model: CompanionViewModel

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            if let bubble = model.bubble {
                Group {
                    if let content = model.bubbleContent {
                        content(bubble)
                    } else if case .text(let t) = bubble {
                        Text(t).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .background(GeometryReader { g in
                    Color.clear.preference(key: BubbleFrameKey.self, value: g.frame(in: .named("panel")))
                })
                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
            }
            DroneView(state: model.state, bankDegrees: model.bankDegrees)
                .contentShape(Ellipse())
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                        .onChanged { _ in model.onDrag?(.changed) }
                        .onEnded { _ in model.onDrag?(.ended) }
                )
                .onTapGesture(count: 2) { model.onDoubleClick?() }
                .padding(.bottom, DronePanel.droneBottomMargin)
        }
        .frame(width: DronePanel.size.width, height: DronePanel.size.height)
        .coordinateSpace(name: "panel")
        .animation(.spring(duration: 0.35, bounce: 0.25), value: model.bubble)
        .onPreferenceChange(BubbleFrameKey.self) { rect in
            let flipped = rect.map { CGRect(x: $0.minX, y: DronePanel.size.height - $0.maxY, width: $0.width, height: $0.height) }
            MainActor.assumeIsolated {
                model.bubbleRect = model.bubble == nil ? nil : flipped
            }
        }
        .onChange(of: model.bubble == nil) { _, isNil in
            if isNil { model.bubbleRect = nil }
        }
    }
}

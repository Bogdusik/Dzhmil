import SwiftUI
import DzhmilCore

enum BubbleStyle {
    static let fill = Color(hex: 0xFFFFFF)
    static let ink = Color(hex: 0x0F2420)
    static let muted = Color(hex: 0x55706A)
    static let accent = Color(hex: 0x008F74)
    static let code = Color(hex: 0xEEF4F2)
    static let maxWidth: CGFloat = 260
}

struct BubbleView: View {
    let bubble: Bubble
    var onAnswer: (Bool) -> Void = { _ in }
    var onSubmit: (String) -> Void = { _ in }
    var onReply: () -> Void = {}
    var onLater: () -> Void = {}
    var onCancel: () -> Void = {}

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        content
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(BubbleStyle.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: BubbleStyle.maxWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(BubbleShape().fill(BubbleStyle.fill).shadow(color: .black.opacity(0.18), radius: 9, y: 4))
            .padding(.bottom, 6)
            .onExitCommand { onCancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch bubble {
        case .text(let text):
            scrolling(Text(text).frame(maxWidth: .infinity, alignment: .leading), maxHeight: 170)

        case .question(let text):
            VStack(alignment: .leading, spacing: 9) {
                Text(text)
                HStack(spacing: 8) {
                    BubbleButton(title: "Ответить", primary: true, action: onReply)
                    BubbleButton(title: "Потом", action: onLater)
                }
            }

        case .confirm(let request):
            VStack(alignment: .leading, spacing: 9) {
                Text(request.question).font(.system(size: 14, weight: .semibold))
                if let detail = request.detail, !detail.isEmpty {
                    scrolling(
                        Text(detail)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8),
                        maxHeight: 110
                    )
                    .background(BubbleStyle.code, in: RoundedRectangle(cornerRadius: 8))
                }
                HStack(spacing: 8) {
                    BubbleButton(title: "Да", primary: true) { onAnswer(true) }
                    BubbleButton(title: "Нет") { onAnswer(false) }
                }
                Text("Можно ответить голосом")
                    .font(.system(size: 11))
                    .foregroundStyle(BubbleStyle.muted)
            }

        case .input:
            TextField("Напиши Джмилю…", text: $draft)
                .textFieldStyle(.plain)
                .focused($focused)
                .frame(width: 230)
                .onSubmit(send)
                .onAppear { focused = true }

        case .onboardingKey(let message):
            VStack(alignment: .leading, spacing: 9) {
                Text(message)
                SecureField("sk-ant-…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(send)
                    .onAppear { focused = true }
                BubbleButton(title: "Сохранить", primary: true, action: send)
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        onSubmit(text)
    }

    private func scrolling(_ view: some View, maxHeight: CGFloat) -> some View {
        ScrollView { view }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maxHeight)
    }
}

private struct BubbleButton: View {
    let title: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(primary ? .white : BubbleStyle.ink)
                .background(primary ? BubbleStyle.accent : BubbleStyle.code, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        var p = Path(roundedRect: body, cornerRadius: 14, style: .continuous)
        let mid = rect.midX
        p.move(to: CGPoint(x: mid - 7, y: body.maxY - 0.5))
        p.addLine(to: CGPoint(x: mid, y: body.maxY + 7))
        p.addLine(to: CGPoint(x: mid + 7, y: body.maxY - 0.5))
        p.closeSubpath()
        return p
    }
}

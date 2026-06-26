import SwiftUI

struct OnboardingOverlay: View {
    @Binding var selectedTab: Int
    @AppStorage("kiku.onboardingCompleted") private var completed = false
    @State private var step = 0
    @State private var displayedText = ""
    @State private var typewriterDone = false
    @State private var typewriterTask: Task<Void, Never>?

    private let steps: [OnboardingStep] = [
        OnboardingStep(tab: 0, text: "このボタンから友達に\n質問を送ろう！",
                       bubbleY: 0.38, tailX: 0.5, tail: .down),
        OnboardingStep(tab: 1, text: "送った質問の回答は\nここに届くよ",
                       bubbleY: 0.50, tailX: 0.5, tail: .up),
        OnboardingStep(tab: 3, text: "みんなの平均返信時間がわかるよ！\n誰よりも早く返信して\nシゴできを目指そう！",
                       bubbleY: 0.55, tailX: 0.5, tail: .up),
        OnboardingStep(tab: 4, text: "ここから友達を追加しよう！",
                       bubbleY: 0.48, tailX: 0.7, tail: .up),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()

                // Skip button
                VStack {
                    HStack {
                        Spacer()
                        Button("スキップ") {
                            typewriterTask?.cancel()
                            completed = true
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    Spacer()
                }

                // Callout + indicators
                let current = steps[step]
                let bubbleTop = geo.size.height * current.bubbleY

                VStack(spacing: 12) {
                    calloutView(screenWidth: geo.size.width, step: current)

                    HStack(spacing: 8) {
                        ForEach(0..<steps.count, id: \.self) { i in
                            Circle()
                                .fill(i == step ? .white : .white.opacity(0.3))
                                .frame(width: 7, height: 7)
                        }
                    }

                    Text(step < steps.count - 1 ? "タップして次へ" : "タップしてはじめる")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(typewriterDone ? 0.5 : 0))
                        .animation(.easeIn(duration: 0.3), value: typewriterDone)
                }
                .padding(.horizontal, 24)
                .position(x: geo.size.width / 2, y: bubbleTop)
            }
            .contentShape(Rectangle())
            .onTapGesture { advance() }
        }
        .onAppear { applyStep() }
    }

    @ViewBuilder
    private func calloutView(screenWidth: CGFloat, step current: OnboardingStep) -> some View {
        Text(displayedText)
            .font(.system(size: 17, weight: .medium))
            .multilineTextAlignment(.center)
            .lineSpacing(6)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(
                CalloutShape(tailX: current.tailX, tailDirection: current.tail)
                    .fill(Color(white: 0.18))
            )
    }

    private func advance() {
        typewriterTask?.cancel()
        if step < steps.count - 1 {
            step += 1
            applyStep()
        } else {
            completed = true
        }
    }

    private func applyStep() {
        selectedTab = steps[step].tab
        displayedText = ""
        typewriterDone = false
        typewriterTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            for char in steps[step].text {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                await MainActor.run { displayedText += String(char) }
            }
            await MainActor.run { typewriterDone = true }
        }
    }
}

// MARK: - Step

private struct OnboardingStep {
    let tab: Int
    let text: String
    let bubbleY: CGFloat
    let tailX: CGFloat
    let tail: TailDirection
}

// MARK: - Tail Direction

private enum TailDirection {
    case up, down
}

// MARK: - Callout Shape

private struct CalloutShape: Shape {
    let tailX: CGFloat
    let tailDirection: TailDirection

    func path(in rect: CGRect) -> Path {
        let tailH: CGFloat = 10
        let tailW: CGFloat = 18
        let r: CGFloat = 16

        let body: CGRect
        switch tailDirection {
        case .down:
            body = CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width, height: rect.height - tailH)
        case .up:
            body = CGRect(x: rect.minX, y: rect.minY + tailH,
                          width: rect.width, height: rect.height - tailH)
        }

        let cx = body.minX + body.width * tailX
        var p = Path()

        p.move(to: CGPoint(x: body.minX + r, y: body.minY))

        // Top edge
        if tailDirection == .up {
            p.addLine(to: CGPoint(x: cx - tailW / 2, y: body.minY))
            p.addLine(to: CGPoint(x: cx, y: body.minY - tailH))
            p.addLine(to: CGPoint(x: cx + tailW / 2, y: body.minY))
        }
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))

        // Top-right corner
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.minY + r),
                 radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        // Right edge
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        // Bottom-right corner
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.maxY - r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)

        // Bottom edge
        if tailDirection == .down {
            p.addLine(to: CGPoint(x: cx + tailW / 2, y: body.maxY))
            p.addLine(to: CGPoint(x: cx, y: body.maxY + tailH))
            p.addLine(to: CGPoint(x: cx - tailW / 2, y: body.maxY))
        }
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))

        // Bottom-left corner
        p.addArc(center: CGPoint(x: body.minX + r, y: body.maxY - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        // Left edge
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        // Top-left corner
        p.addArc(center: CGPoint(x: body.minX + r, y: body.minY + r),
                 radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        p.closeSubpath()
        return p
    }
}

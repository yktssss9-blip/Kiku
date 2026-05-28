import SwiftUI

struct AnswerView: View {
    let question: Question
    let memberId: UUID
    let memberName: String
    let memberEmoji: String

    @EnvironmentObject private var questionStore: QuestionStore
    @Environment(\.dismiss) private var dismiss

    // MARK: - Step

    private enum Step { case initial, time }
    @State private var step: Step = .initial
    @State private var selectedYesNo: String = ""   // "yes" or "no"
    @State private var timeDate: Date = Date()
    @State private var answered: String? = nil
    @State private var hoveredStar: Int = 0

    private var choices: [AnswerChoice] { question.answerChoices }
    private var hasYesNo: Bool { choices.contains(.yes) || choices.contains(.no) }
    private var hasTime:  Bool { choices.contains(.time) }
    private var hasStar:  Bool { choices.contains(.star) }
    private var hasEmoji: Bool { choices.contains(.emoji) }

    private static let emojiOptions = [
        "😊","😍","🥰","😂","😭","😡","😮","🤔",
        "👍","👎","🔥","❤️","💯","🎉","💪","🤯"
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.top, 48)
                    .padding(.horizontal, 24)
                Spacer()
                questionSection
                    .padding(.horizontal, 24)
                Spacer()
                if answered != nil {
                    confirmedSection
                        .padding(.bottom, 48)
                } else {
                    switch step {
                    case .initial:
                        answersSection
                            .padding(.horizontal, 24)
                            .padding(.bottom, 48)
                    case .time:
                        timeSection
                            .padding(.horizontal, 24)
                            .padding(.bottom, 48)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("きく")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(memberEmoji).font(.title3)
                    Text("\(memberName)さんへの質問")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Question

    private var questionSection: some View {
        VStack(spacing: 20) {
            Text(memberEmoji).font(.system(size: 72))
            Text(question.text)
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - 全選択肢セクション

    @ViewBuilder
    private var answersSection: some View {
        VStack(spacing: 16) {
            if hasYesNo {
                yesNoRow
            }
            if hasStar {
                starRow
            }
            if hasEmoji {
                emojiGrid
            }
        }
    }

    // MARK: - ○ / × 行

    private var yesNoRow: some View {
        HStack(spacing: 20) {
            if choices.contains(.yes) {
                Button { pressedYes() } label: {
                    VStack(spacing: 10) {
                        Text("○")
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(.green)
                        if hasTime {
                            subLabel(icon: "clock", text: "時刻を選ぶ", color: .green)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.green.opacity(0.35), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }

            if choices.contains(.no) {
                Button { pressedNo() } label: {
                    VStack(spacing: 10) {
                        Text("✕")
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(Color.red.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.red.opacity(0.28), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 星評価行

    private var starRow: some View {
        VStack(spacing: 12) {
            Text("星で評価してください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        submitAnswer("star:\(n)")
                    } label: {
                        Text(n <= hoveredStar ? "★" : "☆")
                            .font(.system(size: 52))
                            .foregroundStyle(n <= hoveredStar ? Color.orange : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        hoveredStar = inside ? n : 0
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in hoveredStar = n }
                            .onEnded   { _ in hoveredStar = 0 }
                    )
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 1.5)
            )
        }
    }

    // MARK: - 絵文字グリッド

    private var emojiGrid: some View {
        VStack(spacing: 12) {
            Text("絵文字で反応してください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 4),
                spacing: 8
            ) {
                ForEach(Self.emojiOptions, id: \.self) { emoji in
                    Button {
                        submitAnswer("emoji:\(emoji)")
                    } label: {
                        Text(emoji)
                            .font(.system(size: 36))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.yellow.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1.5)
            )
        }
    }

    private func subLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2)
        }
        .foregroundStyle(color.opacity(0.8))
    }

    // MARK: - Step 2a: 時刻ピッカー（○ の後）

    private var timeSection: some View {
        VStack(spacing: 16) {
            HStack {
                backButton { withAnimation(.spring(response: 0.3)) { step = .initial } }
                Spacer()
                selectedBadge
            }

            Text("時刻を選んでください")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            DatePicker("時刻", selection: $timeDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

            Button {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                submitAnswer(formatter.string(from: timeDate))
            } label: {
                primaryButtonLabel(
                    icon: "clock.fill",
                    text: "この時刻で回答",
                    color: .blue
                )
            }
        }
    }

    // MARK: - Confirmed

    private var confirmedSection: some View {
        VStack(spacing: 16) {
            confirmedIcon
                .transition(.scale.combined(with: .opacity))

            Text("「\(displayValue(answered ?? ""))」で回答しました")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button("閉じる") { dismiss() }
                .font(.body)
                .foregroundStyle(.blue)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var confirmedIcon: some View {
        let v = answered ?? ""
        if v == "yes" || v.hasPrefix("yes:") {
            Text("○")
                .font(.system(size: 80, weight: .bold))
                .foregroundStyle(.green)
        } else if v == "no" || v.hasPrefix("no:") {
            Text("✕")
                .font(.system(size: 80, weight: .bold))
                .foregroundStyle(.red)
        } else if isTimeValue(v) {
            Image(systemName: "clock.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
        } else if v.hasPrefix("star:") {
            let n = Int(v.dropFirst(5)) ?? 0
            Text(String(repeating: "★", count: n) + String(repeating: "☆", count: 5 - n))
                .font(.system(size: 40))
                .foregroundStyle(.orange)
        } else if v.hasPrefix("emoji:") {
            Text(String(v.dropFirst(6)))
                .font(.system(size: 80))
        } else {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 64))
                .foregroundStyle(.purple)
        }
    }

    // MARK: - Shared UI Parts

    private var selectedBadge: some View {
        let isYes = selectedYesNo == "yes"
        return Text(isYes ? "○ で回答中" : "✕ で回答中")
            .font(.caption).fontWeight(.semibold)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(isYes ? Color.green.opacity(0.12) : Color.red.opacity(0.10))
            .foregroundStyle(isYes ? .green : .red)
            .clipShape(Capsule())
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("戻る")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func primaryButtonLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.title3)
            Text(text).font(.body).fontWeight(.bold)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity).frame(height: 56)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func displayValue(_ value: String) -> String {
        switch value {
        case "yes": return "○"
        case "no":  return "✕"
        default:
            if value.hasPrefix("yes:")   { return "○ \(value.dropFirst(4))" }
            if value.hasPrefix("no:")    { return "✕ \(value.dropFirst(3))" }
            if value.hasPrefix("star:")  {
                let n = Int(value.dropFirst(5)) ?? 0
                return String(repeating: "★", count: n) + String(repeating: "☆", count: 5 - n)
            }
            if value.hasPrefix("emoji:") { return String(value.dropFirst(6)) }
            return value
        }
    }

    // MARK: - Actions

    private func pressedYes() {
        selectedYesNo = "yes"
        if hasTime {
            withAnimation(.spring(response: 0.3)) { step = .time }
        } else {
            submitAnswer("yes")
        }
    }

    private func pressedNo() {
        submitAnswer("no")
    }

    private func submitAnswer(_ value: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            answered = value
        }
        questionStore.submit(questionId: question.id, memberId: memberId, value: value)
        Task {
            await ActivityManager.shared.end(questionId: question.id, memberId: memberId)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { dismiss() }
        }
    }
}

#Preview {
    let q = Question(
        text:    "今夜ご飯食べる？",
        groupId: UUID(),
        answers: [Answer(memberId: UUID(), value: "pending")],
        choices: ["yes", "no", "time", "freeText"]
    )
    AnswerView(
        question:    q,
        memberId:    q.answers[0].memberId,
        memberName:  "お母さん",
        memberEmoji: "👩"
    )
    .environmentObject(QuestionStore())
}

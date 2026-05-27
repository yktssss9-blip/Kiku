import SwiftUI

struct AnswerView: View {
    let question: Question
    let memberId: UUID
    let memberName: String
    let memberEmoji: String

    @EnvironmentObject private var questionStore: QuestionStore
    @Environment(\.dismiss) private var dismiss

    @State private var answered:      String? = nil   // 回答済み値
    @State private var timeInput:     Date    = Date()
    @State private var freeTextInput: String  = ""

    private var choices: [AnswerChoice] { question.answerChoices }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                    .padding(.top, 48)
                    .padding(.horizontal, 24)
                Spacer()
                questionSection
                    .padding(.horizontal, 24)
                Spacer()
                if answered == nil {
                    buttonSection
                        .padding(.horizontal, 24)
                        .padding(.bottom, 48)
                } else {
                    confirmedSection
                        .padding(.bottom, 48)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Subviews

    private var background: some View {
        LinearGradient(
            colors: answered == "yes"
                ? [Color.green.opacity(0.15), Color.white]
                : answered == "no"
                    ? [Color.gray.opacity(0.1), Color.white]
                    : [Color.blue.opacity(0.08), Color.white],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

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

    // choices に応じてボタンを動的生成
    private var buttonSection: some View {
        VStack(spacing: 14) {
            ForEach(choices) { choice in
                choiceButton(for: choice)
            }
        }
    }

    @ViewBuilder
    private func choiceButton(for choice: AnswerChoice) -> some View {
        switch choice {
        case .yes:
            Button { submitAnswer("yes") } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.title2)
                    Text("はい").font(.title2).fontWeight(.bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 72)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .green.opacity(0.4), radius: 8, y: 4)
            }

        case .no:
            Button { submitAnswer("no") } label: {
                HStack(spacing: 12) {
                    Image(systemName: "xmark.circle.fill").font(.title2)
                    Text("いいえ").font(.title2).fontWeight(.bold)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity).frame(height: 72)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            }

        case .time:
            VStack(spacing: 8) {
                DatePicker(
                    "時刻を選択",
                    selection: $timeInput,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Button {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    submitAnswer(formatter.string(from: timeInput))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill").font(.title2)
                        Text("この時刻で回答").font(.title2).fontWeight(.bold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
                }
            }

        case .freeText:
            VStack(spacing: 8) {
                TextField("自由に入力…", text: $freeTextInput, axis: .vertical)
                    .font(.body)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    let trimmed = freeTextInput.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    submitAnswer(trimmed)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble.fill").font(.title2)
                        Text("回答する").font(.title2).fontWeight(.bold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .purple.opacity(0.4), radius: 8, y: 4)
                }
                .disabled(freeTextInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var confirmedSection: some View {
        VStack(spacing: 16) {
            Image(systemName: answered == "yes"
                  ? "checkmark.circle.fill"
                  : answered == "no"
                    ? "xmark.circle.fill"
                    : "bubble.left.fill")
                .font(.system(size: 64))
                .foregroundStyle(answered == "yes" ? .green : answered == "no" ? .secondary : .blue)
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

    // MARK: - Helpers

    private func displayValue(_ value: String) -> String {
        switch value {
        case "yes": return "はい"
        case "no":  return "いいえ"
        default:    return value
        }
    }

    // MARK: - Action

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

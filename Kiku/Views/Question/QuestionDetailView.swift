import SwiftUI

struct QuestionDetailView: View {
    let question: Question
    let group: KikuGroup
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var pointStore:    PointStore

    @State private var showReminderAlert = false
    @State private var reminderCount = 0

    // 未回答メンバー一覧
    private var pendingAnswers: [Answer] {
        question.answers.filter { $0.value == "pending" }
    }

    private var currentQuestion: Question {
        questionStore.questions.first { $0.id == question.id } ?? question
    }

    var body: some View {
        List {
            Section { summaryCard }

            Section {
                Button {
                    sendReminders()
                } label: {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(pendingAnswers.isEmpty ? Color.secondary : Color.orange)
                        Text("未回答者にリマインドを送る")
                            .foregroundStyle(pendingAnswers.isEmpty ? .secondary : .primary)
                        Spacer()
                        if !pendingAnswers.isEmpty {
                            Text("\(pendingAnswers.count)人")
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                }
                .disabled(pendingAnswers.isEmpty)
            }

            Section("メンバーの回答") {
                ForEach(currentQuestion.answers, id: \.memberId) { answer in
                    answerRow(answer)
                }
            }
        }
        .navigationTitle(question.text)
        .navigationBarTitleDisplayMode(.inline)
        .alert("リマインドを送りました", isPresented: $showReminderAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(reminderCount)人の未回答メンバーに再通知しました")
        }
    }

    // MARK: - リマインド送信

    private func sendReminders() {
        let targets = pendingAnswers.compactMap { answer -> (answer: Answer, friend: Friend)? in
            guard let friend = friendStore.friend(for: answer.memberId) else { return nil }
            return (answer, friend)
        }

        for target in targets {
            NotificationManager.shared.scheduleQuestion(
                questionId:   question.id,
                memberId:     target.friend.id,
                memberName:   target.friend.name,
                memberEmoji:  target.friend.emoji,
                questionText: question.text,
                choices:      currentQuestion.answerChoices
            )
        }

        reminderCount = targets.count
        showReminderAlert = true
    }

    // MARK: - Subviews

    private var summaryCard: some View {
        let s = currentQuestion.summary()
        return HStack(spacing: 0) {
            summaryItem(label: "○",   count: s.yes,     color: .green)
            Divider()
            summaryItem(label: "✕", count: s.no,      color: .red)
            Divider()
            summaryItem(label: "未回答", count: s.pending, color: .orange)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func summaryItem(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)人")
                .font(.title2).fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func answerRow(_ answer: Answer) -> some View {
        let friend = friendStore.friend(for: answer.memberId)

        // この質問でこのメンバーが獲得したポイント記録
        let record = pointStore.records.first {
            $0.questionId == question.id && $0.memberId == answer.memberId
        }

        return HStack {
            Text(friend?.emoji ?? "👤").font(.title3)
            Text(friend?.name  ?? "不明").font(.body)
            Spacer()
            // 回答済みならポイントティアを表示
            if let record {
                Text(record.tier.pointLabel)
                    .font(.caption2)
                    .foregroundStyle(tierColor(record.tier))
                    .padding(.trailing, 4)
            }
            badge(for: answer.value)
        }
        .padding(.vertical, 2)
    }

    private func tierColor(_ tier: PointTier) -> Color {
        switch tier {
        case .fast:   return .orange
        case .normal: return .blue
        case .late:   return .secondary
        }
    }

    private func badge(for value: String) -> some View {
        if value == "pending" {
            return badgePill("⏳ 未回答", bg: Color.orange.opacity(0.15), fg: .orange)
        } else if value == "yes" {
            return badgePill("○ はい", bg: Color.green.opacity(0.12), fg: .green)
        } else if value == "no" {
            return badgePill("✕ いいえ", bg: Color.red.opacity(0.10), fg: .red)
        } else if isTimeValue(value) {
            return badgePill("🕐 \(value)", bg: Color.blue.opacity(0.12), fg: .blue)
        } else if value.hasPrefix("yes:") {
            let text = String(value.dropFirst(4))
            return badgePill("○ \(text)", bg: Color.green.opacity(0.10), fg: .green)
        } else if value.hasPrefix("no:") {
            let text = String(value.dropFirst(3))
            return badgePill("✕ \(text)", bg: Color.red.opacity(0.08), fg: .red)
        } else {
            // レガシーな自由記述値
            return badgePill("💬 \(value)", bg: Color.purple.opacity(0.12), fg: .purple)
        }
    }

    private func badgePill(_ label: String, bg: Color, fg: Color) -> AnyView {
        AnyView(
            Text(label)
                .font(.caption).fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(bg)
                .foregroundStyle(fg)
                .clipShape(Capsule())
        )
    }
}

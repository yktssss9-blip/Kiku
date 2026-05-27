import SwiftUI

struct QuestionFeedCard: View {
    var question: Question
    var friends: [Friend]

    @EnvironmentObject var questionStore: QuestionStore
    @EnvironmentObject var groupStore: GroupStore
    @EnvironmentObject var profileStore: ProfileStore

    @State private var showReminderAlert = false
    @State private var reminderCount = 0

    // questionStore の変更をリアルタイムに反映
    private var currentQuestion: Question {
        questionStore.questions.first { $0.id == question.id } ?? question
    }

    private var summary: (yes: Int, no: Int, pending: Int) {
        currentQuestion.summary()
    }

    // QuestionDetailView の遷移先グループ。
    // broadcast や group が見つからない場合は answers から仮グループを生成
    private var destinationGroup: KikuGroup {
        if let gid = currentQuestion.groupId,
           let found = groupStore.groups.first(where: { $0.id == gid }) {
            return found
        }
        return KikuGroup(
            name: "",
            memberIds: currentQuestion.answers.map(\.memberId)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ─── 上段：アバター / 質問文 / タップボタン ───
            HStack(alignment: .top, spacing: 10) {

                profileAvatarView

                VStack(alignment: .leading, spacing: 6) {

                    HStack(alignment: .top) {
                        Text(currentQuestion.text)
                            .font(.body)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()

                        NavigationLink(
                            destination: QuestionDetailView(
                                question: currentQuestion,
                                group: destinationGroup
                            )
                        ) {
                            HStack(spacing: 2) {
                                Text("タップ")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // ─── 集計行：各回答を独立したチップで表示 ───
                    HStack(spacing: 6) {
                        summaryChip(icon: "○", count: summary.yes,     color: .green)
                        summaryChip(icon: "✕", count: summary.no,      color: .red)
                        summaryChip(icon: "💬", count: summary.pending, color: .orange, suffix: "未回答")
                    }
                }
            }

            // ─── リマインダー行（未回答者がいるときのみ表示）───
            if summary.pending > 0 {
                Button(action: sendReminders) {
                    Label("未回答にリマインダーを送る", systemImage: "bell.badge.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .alert("リマインドを送りました", isPresented: $showReminderAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(reminderCount)人の未回答メンバーに再通知しました")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var profileAvatarView: some View {
        if let photo = profileStore.profileImage {
            photo
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(Circle())
        } else {
            Text(profileStore.emoji)
                .font(.system(size: 22))
                .frame(width: 38, height: 38)
                .background(Color(UIColor.tertiarySystemBackground))
                .clipShape(Circle())
        }
    }

    private func summaryChip(
        icon: String,
        count: Int,
        color: Color,
        suffix: String = ""
    ) -> some View {
        HStack(spacing: 3) {
            Text(icon)
                .foregroundStyle(count == 0 ? .secondary : color)
            Text(suffix.isEmpty ? "\(count)人" : "\(count)人 \(suffix)")
                .foregroundStyle(count == 0 ? .secondary : color)
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(count == 0 ? Color.secondary.opacity(0.08) : color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(count == 0 ? Color.secondary.opacity(0.25) : color.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func sendReminders() {
        let pending = currentQuestion.answers.filter { $0.value == "pending" }
        let targets: [(Answer, Friend)] = pending.compactMap { answer in
            guard let friend = friends.first(where: { $0.id == answer.memberId })
            else { return nil }
            return (answer, friend)
        }
        for (_, friend) in targets {
            NotificationManager.shared.scheduleQuestion(
                questionId:   currentQuestion.id,
                memberId:     friend.id,
                memberName:   friend.name,
                memberEmoji:  friend.emoji,
                questionText: currentQuestion.text,
                choices:      currentQuestion.answerChoices
            )
        }
        reminderCount = targets.count
        showReminderAlert = true
    }
}

import SwiftUI

struct QuestionFeedCard: View {
    var question: Question
    var friends: [Friend]

    @EnvironmentObject var questionStore: QuestionStore
    @EnvironmentObject var groupStore: GroupStore
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var chatStore: ChatStore

    @State private var showReminderAlert = false
    @State private var reminderCount = 0

    // questionStore の変更をリアルタイムに反映
    private var currentQuestion: Question {
        questionStore.questions.first { $0.id == question.id } ?? question
    }

    private var summary: (yes: Int, no: Int, pending: Int) {
        currentQuestion.summary()
    }

    // この質問に紐づくチャットセッション
    private var chatSession: ChatSession? {
        chatStore.sessions.first { $0.questionId == currentQuestion.id }
    }

    // QuestionDetailView の遷移先グループ
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
        VStack(spacing: 0) {

            // ─── メインコンテンツ行 ───
            HStack(spacing: 12) {

                // 左: プロフィールアバター（色付き丸）
                profileAvatarView

                // 中央: 質問文 + 集計ピル
                VStack(alignment: .leading, spacing: 6) {
                    Text(currentQuestion.text)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        statPill(icon: "○", count: summary.yes, color: .green)
                        statPill(icon: "✕", count: summary.no,  color: .red)
                        if summary.pending > 0 {
                            statPill(icon: "💬", count: summary.pending, color: .orange, suffix: "未回答")
                        }
                    }
                }

                Spacer()

                // 右: 詳細への chevron
                NavigationLink(
                    destination: QuestionDetailView(
                        question: currentQuestion,
                        group: destinationGroup
                    )
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            // ─── リマインドボタン（未回答がいるときのみ）───
            if summary.pending > 0 {
                Divider()
                    .padding(.horizontal, 14)

                Button(action: sendReminders) {
                    HStack(spacing: 5) {
                        Image(systemName: "bell.badge.fill")
                            .font(.caption)
                        Text("未回答にリマインダーを送る")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            // ─── チャットボタン（セッションがあるときのみ）───
            if let session = chatSession {
                Divider()
                    .padding(.horizontal, 14)

                NavigationLink(destination: ChatView(session: session)) {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.caption)
                        Text("チャットを見る")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.blue.opacity(0.5))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .alert("リマインドを送りました", isPresented: $showReminderAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(reminderCount)人の未回答メンバーに再通知しました")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var profileAvatarView: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 44, height: 44)

            if let photo = profileStore.profileImage {
                photo
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Text(profileStore.emoji)
                    .font(.system(size: 24))
            }
        }
    }

    @ViewBuilder
    private func statPill(
        icon: String,
        count: Int,
        color: Color,
        suffix: String = ""
    ) -> some View {
        HStack(spacing: 3) {
            Text(icon)
                .font(.caption2)
            Text(suffix.isEmpty ? "\(count)" : "\(count)\(suffix)")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(count == 0 ? Color.secondary : color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((count == 0 ? Color.secondary : color).opacity(0.1))
        .clipShape(Capsule())
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

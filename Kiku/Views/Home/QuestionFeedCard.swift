import SwiftUI

struct QuestionFeedCard: View {
    var question: Question
    var friends: [Friend]

    @EnvironmentObject var questionStore: QuestionStore
    @EnvironmentObject var groupStore:    GroupStore
    @EnvironmentObject var profileStore:  ProfileStore
    @EnvironmentObject var chatStore:     ChatStore

    @State private var showReminderAlert = false
    @State private var reminderCount     = 0

    private var currentQuestion: Question {
        questionStore.questions.first { $0.id == question.id } ?? question
    }

    private var summary: (yes: Int, no: Int, pending: Int) {
        currentQuestion.summary()
    }

    private var destinationGroup: KikuGroup {
        if let gid = currentQuestion.groupId,
           let found = groupStore.groups.first(where: { $0.id == gid }) {
            return found
        }
        return KikuGroup(name: "", memberIds: currentQuestion.answers.map(\.memberId))
    }

    // 回答済み（速い順）→ 未回答の順に並べる
    private var sortedAnswers: [Answer] {
        let answered = currentQuestion.answers
            .filter { $0.value != "pending" }
            .sorted { ($0.answeredAt ?? .distantFuture) < ($1.answeredAt ?? .distantFuture) }
        let pending = currentQuestion.answers.filter { $0.value == "pending" }
        return answered + pending
    }

    var body: some View {
        VStack(spacing: 0) {

            // ─── 質問文 ───
            NavigationLink(
                destination: QuestionDetailView(question: currentQuestion, group: destinationGroup)
            ) {
                HStack(spacing: 10) {
                    Text(currentQuestion.text)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal, 14)

            // ─── メンバー回答一覧 ───
            VStack(spacing: 0) {
                ForEach(Array(sortedAnswers.enumerated()), id: \.element.memberId) { index, answer in
                    memberRow(answer: answer)
                    if index < sortedAnswers.count - 1 {
                        Divider()
                            .padding(.leading, 50)
                            .padding(.trailing, 14)
                    }
                }
            }
            .padding(.vertical, 4)

            // ─── リマインドボタン ───
            if summary.pending > 0 {
                Divider().padding(.horizontal, 14)
                Button(action: sendReminders) {
                    HStack(spacing: 5) {
                        Image(systemName: "bell.badge.fill").font(.caption)
                        Text("未回答にリマインド").font(.caption).fontWeight(.medium)
                    }
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .alert("リマインドを送りました", isPresented: $showReminderAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(reminderCount)人の未回答メンバーに再通知しました")
        }
    }

    // MARK: - Member Row

    @ViewBuilder
    private func memberRow(answer: Answer) -> some View {
        let friend    = friends.first { $0.id == answer.memberId }
        let name      = friend?.name ?? currentQuestion.memberNames[answer.memberId] ?? "不明"
        let isPending = answer.value == "pending"

        HStack(spacing: 10) {
            UserAvatarView(emoji: friend?.emoji ?? "👤", photoURL: friend?.photoURL, size: 34)

            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if isPending {
                pendingIndicator
            } else {
                answeredIndicator(answer: answer)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // 未回答: 経過時間を色つきで表示
    @ViewBuilder
    private var pendingIndicator: some View {
        let elapsed = Date().timeIntervalSince(currentQuestion.createdAt)
        HStack(spacing: 3) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.caption)
            Text(formatElapsed(elapsed))
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(urgencyColor(for: elapsed))
    }

    // 回答済み: 回答アイコン + 速度ティア + 経過時間
    @ViewBuilder
    private func answeredIndicator(answer: Answer) -> some View {
        HStack(spacing: 6) {
            answerIcon(for: answer.value)

            if let answeredAt = answer.answeredAt {
                let elapsed = answeredAt.timeIntervalSince(currentQuestion.createdAt)
                let tier    = PointTier.tier(for: elapsed)
                HStack(spacing: 2) {
                    Text(tierMark(tier)).font(.caption)
                    Text(formatElapsed(elapsed))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func answerIcon(for value: String) -> some View {
        if isTimeValue(value) || value.hasPrefix("star:") || value.hasPrefix("emoji:") {
            Text(shortLabel(for: value))
                .font(.caption).fontWeight(.semibold).foregroundStyle(.blue)
                .lineLimit(1)
        } else if answerIsYes(value) {
            Text("○")
                .font(.caption).fontWeight(.bold).foregroundStyle(.green)
                .frame(width: 20, height: 20)
                .background(Color.green.opacity(0.12))
                .clipShape(Circle())
        } else if answerIsNo(value) {
            Text("✕")
                .font(.caption).fontWeight(.bold).foregroundStyle(.red)
                .frame(width: 20, height: 20)
                .background(Color.red.opacity(0.12))
                .clipShape(Circle())
        } else {
            Text(shortLabel(for: value))
                .font(.caption).fontWeight(.semibold).foregroundStyle(.blue)
                .lineLimit(1)
        }
    }

    // MARK: - Helpers

    private func tierMark(_ tier: PointTier) -> String {
        switch tier {
        case .fast:   return "⚡"
        case .normal: return "🕐"
        default:      return "💬"
        }
    }

    private func urgencyColor(for elapsed: TimeInterval) -> Color {
        elapsed < 5 * 60 ? .orange : .red
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let s = Int(elapsed)
        if s < 60  { return "\(s)秒" }
        let m = s / 60
        if m < 60  { return "\(m)分" }
        let h = m / 60
        if h < 24  { return "\(h)時間" }
        return "\(h / 24)日"
    }

    private func shortLabel(for value: String) -> String {
        if isTimeValue(value)         { return "🕐 \(value)" }
        if value.hasPrefix("yes:")    { return String(value.dropFirst(4).prefix(8)) }
        if value.hasPrefix("no:")     { return String(value.dropFirst(3).prefix(8)) }
        if value.hasPrefix("star:")   { return "⭐ \(value.dropFirst(5))" }
        if value.hasPrefix("emoji:")  { return String(value.dropFirst(6)) }
        return value
    }

    // MARK: - Actions

    private func sendReminders() {
        let pending = currentQuestion.answers.filter { $0.value == "pending" }
        let targets = pending.filter { answer in
            friends.contains { $0.id == answer.memberId }
        }
        reminderCount = targets.count
        if !targets.isEmpty {
            questionStore.sendReminder(questionId: currentQuestion.id)
        }
        showReminderAlert = true
    }
}

import SwiftUI

struct QuestionDetailView: View {
    let question: Question
    let group: KikuGroup
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var pointStore:    PointStore

    @State private var showReminderAlert = false
    @State private var reminderCount = 0
    @State private var answerToReset: Answer? = nil
    @State private var progressAnimated = false
    @State private var showInviteCopied = false

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

                Button {
                    copyInviteLink()
                } label: {
                    HStack {
                        Image(systemName: showInviteCopied ? "checkmark.circle.fill" : "link.badge.plus")
                            .foregroundStyle(showInviteCopied ? Color.green : Color.blue)
                        Text(showInviteCopied ? "コピーしました！" : "招待リンクをコピー")
                            .foregroundStyle(showInviteCopied ? Color.green : Color.primary)
                        Spacer()
                    }
                }
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
        .alert(
            "回答を取り消しますか？",
            isPresented: Binding(
                get: { answerToReset != nil },
                set: { if !$0 { answerToReset = nil } }
            )
        ) {
            Button("取り消す", role: .destructive) {
                if let ans = answerToReset {
                    questionStore.resetAnswer(questionId: currentQuestion.id, memberId: ans.memberId)
                }
                answerToReset = nil
            }
            Button("キャンセル", role: .cancel) {
                answerToReset = nil
            }
        } message: {
            if let ans = answerToReset,
               let friend = friendStore.friend(for: ans.memberId) {
                Text("\(friend.name) さんの回答を「未回答」に戻します。ポイントは取り消されません。")
            } else {
                Text("この回答を「未回答」に戻します。ポイントは取り消されません。")
            }
        }
    }

    // MARK: - 招待リンク

    private func copyInviteLink() {
        let q = currentQuestion
        let inviteURL = "kiku://invite?qid=\(q.id.uuidString)&token=\(q.inviteToken)"
        let message = """
        「\(q.text)」に回答してください！

        アプリからタップ：
        \(inviteURL)

        きくをお持ちでない方はインストール後、上のリンクをタップしてください：
        https://apps.apple.com/jp/app/id0000000000
        """
        UIPasteboard.general.string = message
        withAnimation { showInviteCopied = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { withAnimation { showInviteCopied = false } }
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
        let total = s.yes + s.no + s.pending
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                summaryItem(label: "○",   count: s.yes,     color: .green)
                Divider()
                summaryItem(label: "✕", count: s.no,      color: .red)
                Divider()
                summaryItem(label: "未回答", count: s.pending, color: .orange)
            }
            .frame(maxWidth: .infinity)

            GeometryReader { geo in
                let width = geo.size.width
                if total == 0 {
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                } else {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: CGFloat(s.yes) / CGFloat(total) * width)
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: CGFloat(s.no) / CGFloat(total) * width)
                        Rectangle()
                            .fill(Color.orange.opacity(0.6))
                            .frame(width: CGFloat(s.pending) / CGFloat(total) * width)
                    }
                    .frame(height: 8)
                    .clipShape(Capsule())
                    .scaleEffect(x: progressAnimated ? 1 : 0, anchor: .leading)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 16)

            Text("\(s.yes + s.no)/\(total)人回答済み")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6)) {
                progressAnimated = true
            }
        }
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

        let starComment: String? = {
            guard answer.value.hasPrefix("star:") else { return nil }
            let parts = answer.value.dropFirst(5).split(separator: ":", maxSplits: 1)
            guard parts.count > 1 else { return nil }
            return String(parts[1])
        }()

        return HStack(alignment: starComment != nil ? .top : .center) {
            Text(friend?.emoji ?? "👤").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend?.name ?? "不明").font(.body)
                if let comment = starComment {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
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
        .contextMenu {
            if answer.value != "pending" {
                Button(role: .destructive) {
                    answerToReset = answer
                } label: {
                    Label("回答を取り消す", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    private func tierColor(_ tier: PointTier) -> Color {
        switch tier {
        case .fast:         return .orange
        case .normal:       return .blue
        case .late:         return .secondary
        case .senderFast:   return .orange
        case .senderNormal: return .blue
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
        } else if value.hasPrefix("star:") {
            let parts = value.dropFirst(5).split(separator: ":", maxSplits: 1)
            let n = Int(parts.first ?? "") ?? 0
            let stars = String(repeating: "★", count: n) + String(repeating: "☆", count: 5 - n)
            return badgePill(stars, bg: Color.orange.opacity(0.12), fg: .orange)
        } else if value.hasPrefix("emoji:") {
            let e = String(value.dropFirst(6))
            return badgePill(e, bg: Color.yellow.opacity(0.12), fg: .primary)
        } else {
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

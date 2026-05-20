import SwiftUI

struct QuestionDetailView: View {
    let question: Question
    let group: KikuGroup
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore: FriendStore

    @StateObject private var activityManager = ActivityManager.shared
    @State private var showReminderAlert = false
    @State private var reminderCount = 0

    // 未回答メンバー一覧
    private var pendingAnswers: [Answer] {
        question.answers.filter { $0.value == "pending" }
    }

    var body: some View {
        List {
            // 集計サマリー
            Section {
                summaryCard
            }

            // 未回答リマインドボタン（CORE 05）
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

            // Live Activity 起動
            Section("通知バーで回答") {
                if pendingAnswers.isEmpty {
                    Text("全員回答済みです")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(pendingAnswers, id: \.memberId) { answer in
                        if let friend = friendStore.friend(for: answer.memberId) {
                            Button {
                                activityManager.start(
                                    question: question,
                                    memberId: friend.id,
                                    memberName: friend.name
                                )
                            } label: {
                                HStack {
                                    Text(friend.emoji).font(.title3)
                                    Text("\(friend.name) に送る")
                                    Spacer()
                                    Image(systemName: "bell.badge.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Activityエラー表示
                if let error = activityManager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            // メンバー別回答一覧
            Section("メンバーの回答") {
                ForEach(question.answers, id: \.memberId) { answer in
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
                questionText: question.text
            )
        }

        reminderCount = targets.count
        showReminderAlert = true
    }

    // MARK: - Subviews

    private var summaryCard: some View {
        let s = question.summary()
        return HStack(spacing: 0) {
            summaryItem(label: "はい",   count: s.yes,     color: .green)
            Divider()
            summaryItem(label: "いいえ", count: s.no,      color: .secondary)
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
        return HStack {
            Text(friend?.emoji ?? "👤").font(.title3)
            Text(friend?.name  ?? "不明").font(.body)
            Spacer()
            badge(for: answer.value)
        }
        .padding(.vertical, 2)
    }

    private func badge(for value: String) -> some View {
        switch value {
        case "yes":
            return AnyView(
                Text("✅ はい")
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            )
        case "no":
            return AnyView(
                Text("❌ いいえ")
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            )
        default:
            return AnyView(
                Text("⏳ 未回答")
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            )
        }
    }
}

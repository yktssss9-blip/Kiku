import SwiftUI

struct QuestionDetailView: View {
    let question: Question
    let group: KikuGroup
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore: FriendStore

    @StateObject private var activityManager = ActivityManager.shared
    @State private var showSuccessAlert = false
    @State private var launchedMemberName = ""

    var body: some View {
        List {
            Section {
                summaryCard
            }

            // エラー表示
            if let error = activityManager.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            // Live Activity 起動セクション
            Section("通知バーで回答") {
                ForEach(question.answers.filter { $0.value == "pending" }, id: \.memberId) { answer in
                    if let friend = friendStore.friend(for: answer.memberId) {
                        Button {
                            ActivityManager.shared.start(
                                question: question,
                                memberId: friend.id,
                                memberName: friend.name
                            )
                            launchedMemberName = friend.name
                            showSuccessAlert = activityManager.lastError == nil
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
                if question.answers.filter({ $0.value == "pending" }).isEmpty {
                    Text("全員回答済みです").foregroundStyle(.secondary).font(.subheadline)
                }
            }

            Section("メンバーの回答") {
                ForEach(question.answers, id: \.memberId) { answer in
                    answerRow(answer)
                }
            }
        }
        .navigationTitle(question.text)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        let s = question.summary()
        return HStack(spacing: 0) {
            summaryItem(label: "はい", count: s.yes, color: .green)
            Divider()
            summaryItem(label: "いいえ", count: s.no, color: .secondary)
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
        let emoji  = friend?.emoji ?? "👤"
        let name   = friend?.name  ?? "不明"

        return HStack {
            Text(emoji).font(.title3)
            Text(name).font(.body)
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

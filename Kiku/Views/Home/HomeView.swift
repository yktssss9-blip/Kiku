import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var groupStore:    GroupStore
    @EnvironmentObject private var profileStore:  ProfileStore
    @EnvironmentObject private var chatStore:     ChatStore

    // 自分への未回答バナー用
    private var myPendingCount: Int {
        let myId = profileStore.myId
        return questionStore.questions.reduce(0) { count, q in
            count + q.answers.filter { $0.memberId == myId && $0.value == "pending" }.count
        }
    }

    // 最新順フィード
    private var feedQuestions: [Question] {
        questionStore.questions.sorted { $0.createdAt > $1.createdAt }
    }

    // 未回答者がいる質問（最新順）
    private var pendingQuestions: [Question] {
        feedQuestions.filter { $0.summary().pending > 0 }
    }

    // 全員回答済み（最新順）
    private var completedQuestions: [Question] {
        feedQuestions.filter { $0.summary().pending == 0 }
    }

    @State private var showPendingInbox        = false
    @State private var questionToDelete: Question? = nil
    @State private var showDeleteQuestionAlert  = false
    @State private var isCompletedExpanded      = false
    @State private var isFriendRequestExpanded  = false

    private var hasFriendActivity: Bool {
        !friendStore.pendingRequests.isEmpty || !friendStore.sentRequests.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ─── 自分への未回答バナー ───
                    if myPendingCount > 0 {
                        Button {
                            showPendingInbox = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.badge.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.orange)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("回答待ちの質問があります")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Text("\(myPendingCount)件")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }

                    // ─── 友達申請セクション ───
                    if hasFriendActivity {
                        friendRequestSection
                            .padding(.horizontal, 16)
                    }

                    // ─── 進行中セクション ───
                    if !pendingQuestions.isEmpty {
                        pendingSection
                            .padding(.horizontal, 16)
                    }

                    // ─── 完了セクション ───
                    if !completedQuestions.isEmpty {
                        completedSection
                            .padding(.horizontal, 16)
                    }

                    // ─── 空状態 ───
                    if feedQuestions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "questionmark.bubble")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("質問を送って\n返事を集めよう")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("フィード")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("質問を削除しますか？", isPresented: $showDeleteQuestionAlert, presenting: questionToDelete) { q in
            Button("削除", role: .destructive) {
                questionStore.delete(questionId: q.id)
                questionToDelete = nil
            }
            Button("キャンセル", role: .cancel) { questionToDelete = nil }
        } message: { q in
            Text("「\(q.text)」と回答データをすべて削除します。この操作は元に戻せません。")
        }
        .sheet(isPresented: $showPendingInbox) {
            NotificationInboxView()
                .environmentObject(questionStore)
                .environmentObject(friendStore)
                .environmentObject(profileStore)
        }
    }

    // MARK: - 友達申請セクション

    @ViewBuilder
    private var friendRequestSection: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isFriendRequestExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("友達申請")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    if !friendStore.pendingRequests.isEmpty {
                        Text("\(friendStore.pendingRequests.count)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isFriendRequestExpanded ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            if isFriendRequestExpanded {
                VStack(spacing: 8) {
                    // 受信した申請（pending）
                    ForEach(friendStore.pendingRequests) { request in
                        ReceivedFriendRequestCard(request: request)
                            .environmentObject(friendStore)
                    }
                    // 送信した申請（全ステータス）
                    ForEach(friendStore.sentRequests) { request in
                        SentFriendRequestCard(request: request)
                    }
                }
            }
        }
    }

    // MARK: - 進行中セクション

    @ViewBuilder
    private var pendingSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("進行中")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text("\(pendingQuestions.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(pendingQuestions) { question in
                    questionCard(question)
                }
            }
        }
    }

    // MARK: - 完了セクション

    @ViewBuilder
    private var completedSection: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCompletedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("完了")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Text("\(completedQuestions.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCompletedExpanded ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            if isCompletedExpanded {
                VStack(spacing: 8) {
                    ForEach(completedQuestions) { question in
                        questionCard(question)
                    }
                }
            }
        }
    }

    // MARK: - 質問カード

    @ViewBuilder
    private func questionCard(_ question: Question) -> some View {
        QuestionFeedCard(question: question, friends: friendStore.friends)
            .environmentObject(questionStore)
            .environmentObject(groupStore)
            .environmentObject(profileStore)
            .environmentObject(chatStore)
            .contextMenu {
                Button(role: .destructive) {
                    questionToDelete = question
                    showDeleteQuestionAlert = true
                } label: {
                    Label("質問を削除", systemImage: "trash")
                }
            }
    }

}

// MARK: - Preview

#Preview {
    HomeView()
        .environmentObject(QuestionStore())
        .environmentObject(FriendStore())
        .environmentObject(GroupStore())
        .environmentObject(ProfileStore())
        .environmentObject(ChatStore())
}

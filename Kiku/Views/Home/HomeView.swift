import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var groupStore:    GroupStore
    @EnvironmentObject private var profileStore:  ProfileStore

    private var feedQuestions: [Question] {
        questionStore.questions.sorted { $0.createdAt > $1.createdAt }
    }

    private var pendingQuestions: [Question] {
        feedQuestions.filter { $0.summary().pending > 0 }
    }

    private var completedQuestions: [Question] {
        feedQuestions.filter { $0.summary().pending == 0 }
    }

    @State private var questionToDelete: Question? = nil
    @State private var showDeleteQuestionAlert = false
    @State private var isPendingExpanded   = false
    @State private var isCompletedExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ─── 質問作成エリア ───
                    QuestionComposerView(onSend: handleSend)
                        .padding(.horizontal, 16)

                    // ─── 未回答ありセクション ───
                    if !pendingQuestions.isEmpty {
                        feedSection(
                            icon: "circle.fill",
                            iconColor: .orange,
                            title: "未回答あり",
                            questions: pendingQuestions,
                            isExpanded: $isPendingExpanded
                        )
                        .padding(.horizontal, 16)
                    }

                    // ─── 完了セクション ───
                    if !completedQuestions.isEmpty {
                        feedSection(
                            icon: "checkmark.circle.fill",
                            iconColor: .green,
                            title: "完了",
                            questions: completedQuestions,
                            isExpanded: $isCompletedExpanded
                        )
                        .padding(.horizontal, 16)
                    }

                    // ─── 空状態 ───
                    if feedQuestions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "questionmark.bubble")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("質問を送ってみよう")
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
            .navigationTitle("シゴでき")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("質問を削除しますか？", isPresented: $showDeleteQuestionAlert, presenting: questionToDelete) { q in
            Button("削除", role: .destructive) {
                questionStore.delete(questionId: q.id)
                questionToDelete = nil
            }
            Button("キャンセル", role: .cancel) {
                questionToDelete = nil
            }
        } message: { q in
            Text("「\(q.text)」と回答データをすべて削除します。この操作は元に戻せません。")
        }
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func feedSection(
        icon: String,
        iconColor: Color,
        title: String,
        questions: [Question],
        isExpanded: Binding<Bool>
    ) -> some View {
        VStack(spacing: 10) {
            // セクションヘッダー
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)

                    Text(title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text("\(questions.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(iconColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(iconColor.opacity(0.12))
                        .clipShape(Capsule())

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            // カード一覧
            if isExpanded.wrappedValue {
                VStack(spacing: 8) {
                    ForEach(questions) { question in
                        QuestionFeedCard(
                            question: question,
                            friends:  friendStore.friends
                        )
                        .environmentObject(questionStore)
                        .environmentObject(groupStore)
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
            }
        }
    }

    // MARK: - 送信ロジック

    private func handleSend(
        _ text: String,
        _ friends: [Friend]?,
        _ group: KikuGroup?,
        _ choices: [AnswerChoice]
    ) {
        if let targets = friends, !targets.isEmpty {
            questionStore.sendBroadcast(text: text, to: targets, choices: choices)
        } else if let target = group {
            questionStore.send(text: text, to: target, friends: friendStore.friends, choices: choices)
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

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var groupStore:    GroupStore
    @EnvironmentObject private var profileStore:  ProfileStore

    private var feedQuestions: [Question] {
        questionStore.questions.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // ─── 質問作成エリア ───
                    QuestionComposerView(onSend: handleSend)
                        .padding(.horizontal, 16)

                    // ─── 一回答フィード ───
                    if !feedQuestions.isEmpty {
                        HStack {
                            Text("回答")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)

                        VStack(spacing: 12) {
                            ForEach(feedQuestions) { question in
                                QuestionFeedCard(
                                    question: question,
                                    friends:  friendStore.friends
                                )
                                .environmentObject(questionStore)
                                .environmentObject(groupStore)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("きく")
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

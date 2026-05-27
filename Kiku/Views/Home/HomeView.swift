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

    // グループ管理
    @State private var isGroupsExpanded    = true
    @State private var showGroupCreate     = false
    @State private var groupToEdit:   KikuGroup? = nil
    @State private var groupToDelete: KikuGroup? = nil
    @State private var showDeleteGroupAlert = false

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

                    // ─── グループセクション ───
                    groupSection
                        .padding(.horizontal, 16)

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
        // 質問削除アラート
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
        // グループ削除アラート
        .alert("グループを削除しますか？", isPresented: $showDeleteGroupAlert, presenting: groupToDelete) { g in
            Button("削除", role: .destructive) {
                groupStore.delete(id: g.id)
                groupToDelete = nil
            }
            Button("キャンセル", role: .cancel) {
                groupToDelete = nil
            }
        } message: { g in
            Text("「\(g.name)」とそのグループに送信した質問・回答データをすべて削除します。この操作は元に戻せません。")
        }
        // グループ作成シート
        .sheet(isPresented: $showGroupCreate) {
            GroupCreateView()
                .environmentObject(friendStore)
                .environmentObject(groupStore)
        }
        // グループ編集シート
        .sheet(item: $groupToEdit) { group in
            GroupEditView(group: group)
                .environmentObject(friendStore)
                .environmentObject(groupStore)
        }
    }

    // MARK: - Group Section

    @ViewBuilder
    private var groupSection: some View {
        VStack(spacing: 10) {
            // ヘッダー
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isGroupsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.indigo)

                        Text("グループ")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)

                        if !groupStore.groups.isEmpty {
                            Text("\(groupStore.groups.count)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isGroupsExpanded ? 0 : -90))
                    }
                }
                .buttonStyle(.plain)

                // ＋ グループ作成ボタン
                Button {
                    showGroupCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.indigo)
                        .padding(6)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(Circle())
                }
            }

            // グループ一覧
            if isGroupsExpanded {
                if groupStore.groups.isEmpty {
                    HStack {
                        Text("まだグループがありません")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(groupStore.groups) { group in
                            Button {
                                groupToEdit = group
                            } label: {
                                groupCard(group)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    groupToEdit = group
                                } label: {
                                    Label("グループを編集", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    groupToDelete = group
                                    showDeleteGroupAlert = true
                                } label: {
                                    Label("グループを削除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func groupCard(_ group: KikuGroup) -> some View {
        HStack(spacing: 12) {
            // アイコン
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.indigo)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text("\(group.memberIds.count)人のメンバー")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            // 個人宛送信
            questionStore.sendToIndividuals(text: text, to: targets, choices: choices)
            Task { @MainActor in
                if let question = questionStore.questions.last {
                    for friend in targets {
                        ActivityManager.shared.start(
                            question:   question,
                            memberId:   friend.id,
                            memberName: friend.name
                        )
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }
            }
        } else if let target = group {
            // グループ送信
            questionStore.send(text: text, to: target, friends: friendStore.friends, choices: choices)
            Task { @MainActor in
                if let question = questionStore.questions.last {
                    for memberId in target.memberIds {
                        let friend = friendStore.friends.first { $0.id == memberId }
                        ActivityManager.shared.start(
                            question:   question,
                            memberId:   memberId,
                            memberName: friend?.name ?? "メンバー"
                        )
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }
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

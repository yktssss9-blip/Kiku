import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var groupStore:    GroupStore
    @EnvironmentObject private var profileStore:  ProfileStore
    @EnvironmentObject private var chatStore:     ChatStore
    @EnvironmentObject private var purchaseStore: PurchaseStore

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

    @State private var showPendingInbox      = false
    @State private var questionToDelete: Question? = nil
    @State private var showDeleteQuestionAlert = false
    @State private var isCompletedExpanded   = false

    // グループ管理
    @State private var isGroupsExpanded    = true
    @State private var showGroupCreate     = false
    @State private var groupToEdit:   KikuGroup? = nil
    @State private var groupToDelete: KikuGroup? = nil
    @State private var showDeleteGroupAlert = false

    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ─── 質問作成エリア ───
                    QuestionComposerView(onSend: handleSend)
                        .padding(.horizontal, 16)

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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if profileStore.isStopTimeActive {
                            profileStore.isStopTimeActive = false
                        } else if purchaseStore.isPro || !profileStore.hasUsedFreeStopTimeToday() {
                            profileStore.isStopTimeActive = true
                            if !purchaseStore.isPro { profileStore.recordStopTimeActivation() }
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Image(systemName: profileStore.isStopTimeActive ? "pause.circle.fill" : "pause.circle")
                            .foregroundStyle(profileStore.isStopTimeActive ? Color.orange : Color.secondary)
                            .imageScale(.large)
                    }
                }
            }
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
        .alert("グループを削除しますか？", isPresented: $showDeleteGroupAlert, presenting: groupToDelete) { g in
            Button("削除", role: .destructive) {
                groupStore.delete(id: g.id)
                groupToDelete = nil
            }
            Button("キャンセル", role: .cancel) { groupToDelete = nil }
        } message: { g in
            Text("「\(g.name)」とそのグループに送信した質問・回答データをすべて削除します。この操作は元に戻せません。")
        }
        .sheet(isPresented: $showPendingInbox) {
            NotificationInboxView()
                .environmentObject(questionStore)
                .environmentObject(friendStore)
                .environmentObject(profileStore)
        }
        .sheet(isPresented: $showGroupCreate) {
            GroupCreateView()
                .environmentObject(friendStore)
                .environmentObject(groupStore)
                .environmentObject(purchaseStore)
        }
        .sheet(item: $groupToEdit) { group in
            GroupEditView(group: group)
                .environmentObject(friendStore)
                .environmentObject(groupStore)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(purchaseStore)
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

    // MARK: - グループセクション

    @ViewBuilder
    private var groupSection: some View {
        VStack(spacing: 10) {
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
                            Button { groupToEdit = group } label: { groupCard(group) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { groupToEdit = group } label: {
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

    // MARK: - 送信ロジック

    private func handleSend(
        _ text: String,
        _ friends: [Friend]?,
        _ group: KikuGroup?,
        _ choices: [AnswerChoice],
        _ reminderAfter: TimeInterval?
    ) {
        if let targets = friends, !targets.isEmpty {
            questionStore.sendToIndividuals(text: text, to: targets, choices: choices, reminderAfter: reminderAfter)
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
            questionStore.send(text: text, to: target, friends: friendStore.friends, choices: choices, reminderAfter: reminderAfter)
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
        .environmentObject(PurchaseStore())
}

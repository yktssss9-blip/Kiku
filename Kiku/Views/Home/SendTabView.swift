import SwiftUI

struct SendTabView: View {
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var groupStore:    GroupStore
    @EnvironmentObject private var profileStore:  ProfileStore
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @EnvironmentObject private var templateStore: TemplateStore
    @EnvironmentObject private var reviewManager: ReviewManager

    @State private var selectedFriends: [Friend]   = []
    @State private var selectedGroup:   KikuGroup? = nil
    @State private var questionText:    String     = ""
    @State private var showTemplates:   Bool       = false
    @State private var showStopTimeAlert:    Bool        = false
    @State private var stopTimeNames:        String      = ""
    @State private var choices:              [AnswerChoice] = [.yes, .no]
    @State private var isShowingChoiceMenu:  Bool        = false
    @State private var reminderSeconds:      TimeInterval? = nil
    @State private var isShowingReminderMenu: Bool       = false
    @State private var showPaywall:          Bool        = false
    @State private var searchText:           String      = ""
    @State private var isSearching:          Bool        = false
    @State private var showShareSheet:        Bool        = false
    @State private var shareURL:             URL?        = nil

    @Namespace private var selectionNamespace

    private var canSend: Bool {
        !questionText.trimmingCharacters(in: .whitespaces).isEmpty
            && (!selectedFriends.isEmpty || selectedGroup != nil)
    }

    private var filteredFriends: [Friend] {
        let visible = friendStore.friends.filter { f in
            !friendStore.isBlocked(f.id) && !selectedFriends.contains { $0.id == f.id }
        }
        guard !searchText.isEmpty else { return visible }
        return visible.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // ─── ロゴ ───
                Text("Kiku")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                // ─── 友達横スクロール行 ───
                friendRow

                // ─── グループ横スクロール ───
                if !groupStore.groups.isEmpty {
                    groupScroll
                        .padding(.top, 12)
                }

                // ─── 選択済み表示エリア ───
                selectedRecipientsArea

                // ─── 質問入力 ───
                questionInput
                    .padding(.horizontal, 24)

                Spacer()

                // ─── 選択肢チップ行 ───
                choiceRow
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                // ─── 送信エリア ───
                sendRow
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
        }
        .alert("送信できません", isPresented: $showStopTimeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(stopTimeNames) は現在 Stop Time 中のため、質問を送ることができません。")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showTemplates) {
            if purchaseStore.isPro {
                TemplateListSheet(
                    currentText:      questionText,
                    currentFriendIds: selectedFriends.map(\.id),
                    currentGroupId:   selectedGroup?.id,
                    currentChoices:   choices
                ) { template in
                    applyTemplate(template)
                }
                .environmentObject(templateStore)
                .environmentObject(friendStore)
                .environmentObject(groupStore)
            } else {
                PaywallView()
                    .environmentObject(purchaseStore)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(purchaseStore)
        }
        .task { await friendStore.fetchStopTimeStatuses() }
    }

    // MARK: - 友達横スクロール行

    private var friendRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                searchToggle
                ForEach(filteredFriends) { friend in
                    friendCircle(friend)
                }
                linkSendCircle
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    private var searchToggle: some View {
        Group {
            if isSearching {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    TextField("名前で検索", text: $searchText)
                        .font(.subheadline)
                        .frame(minWidth: 100)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            searchText = ""
                            isSearching = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemFill))
                .clipShape(Capsule())
                .frame(height: 68)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.85).combined(with: .opacity),
                    removal:   .scale(scale: 0.85).combined(with: .opacity)
                ))
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearching = true
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .foregroundStyle(Color(UIColor.separator))
                                .frame(width: 60, height: 60)
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20))
                                .foregroundStyle(.tertiary)
                        }
                        Text("検索")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.85).combined(with: .opacity),
                    removal:   .scale(scale: 0.85).combined(with: .opacity)
                ))
            }
        }
    }

    @ViewBuilder
    private func friendCircle(_ friend: Friend) -> some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                selectedFriends.append(friend)
                selectedGroup = nil
            }
        } label: {
            let isStopTime = friendStore.isStopTime(friend)
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(width: 60, height: 60)
                    UserAvatarView(emoji: friend.emoji, photoURL: friend.photoURL, size: 60)
                    if isStopTime {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)
                            .background(Color(UIColor.systemBackground), in: Circle())
                            .offset(x: 20, y: 20)
                    }
                }
                .grayscale(isStopTime ? 1.0 : 0)
                .opacity(isStopTime ? 0.5 : 1.0)
                .matchedGeometryEffect(id: "avatar_\(friend.id)", in: selectionNamespace)

                Text(friend.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 60)
            }
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private var linkSendCircle: some View {
        let hasText = !questionText.trimmingCharacters(in: .whitespaces).isEmpty
        return Button {
            guard hasText else { return }
            let question = questionStore.sendViaLink(text: questionText.trimmingCharacters(in: .whitespaces), choices: choices)
            let urlString = "https://shigodeki-8e49a.web.app/q/\(question.id.uuidString)?token=\(question.inviteToken)"
            shareURL = URL(string: urlString)
            showShareSheet = true
            questionText    = ""
            selectedFriends = []
            selectedGroup   = nil
            choices         = [.yes, .no]
            reminderSeconds = nil
            reviewManager.onQuestionSent()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(hasText ? Color.blue.opacity(0.12) : Color(UIColor.quaternarySystemFill))
                        .frame(width: 60, height: 60)
                    Circle()
                        .stroke(hasText ? Color.blue.opacity(0.4) : Color(UIColor.separator), lineWidth: 1)
                        .frame(width: 60, height: 60)
                    Image(systemName: "link")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(hasText ? Color.blue : Color(UIColor.tertiaryLabel))
                }
                Text("リンク")
                    .font(.caption2)
                    .foregroundStyle(hasText ? Color.blue : Color(UIColor.tertiaryLabel))
            }
        }
        .buttonStyle(.plain)
        .disabled(!hasText)
    }

    // MARK: - グループ横スクロール

    private var groupScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(groupStore.groups) { group in
                    let isSelected = selectedGroup?.id == group.id
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            if isSelected {
                                selectedGroup = nil
                            } else {
                                selectedGroup   = group
                                selectedFriends = []
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("👥").font(.caption)
                            Text(group.name)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(isSelected ? Color(UIColor.systemBackground) : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.primary : Color(UIColor.tertiarySystemFill))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - 質問入力

    private var questionInput: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom) {
                TextField("今夜来れる？", text: $questionText, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .tint(.primary)
                    .lineLimit(1...4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(questionText.count)/50")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)
            }
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(height: 1)
        }
    }

    // MARK: - 選択済み表示エリア

    private var selectedRecipientsArea: some View {
        ZStack {
            Color.clear.frame(height: 96)

            if !selectedFriends.isEmpty {
                HStack(spacing: selectedFriends.count > 3 ? 8 : 16) {
                    ForEach(selectedFriends) { friend in
                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                                selectedFriends.removeAll { $0.id == friend.id }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(Color(UIColor.tertiarySystemFill))
                                        .frame(width: 64, height: 64)
                                    Circle()
                                        .stroke(Color.primary, lineWidth: 1.5)
                                        .frame(width: 64, height: 64)
                                    UserAvatarView(emoji: friend.emoji, photoURL: friend.photoURL, size: 64)
                                }
                                .matchedGeometryEffect(id: "avatar_\(friend.id)", in: selectionNamespace)

                                Text(friend.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
            } else if let group = selectedGroup {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(width: 64, height: 64)
                        Circle()
                            .stroke(Color.primary, lineWidth: 1.5)
                            .frame(width: 64, height: 64)
                        Text("👥")
                            .font(.system(size: 28))
                    }
                    Text(group.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(group.memberIds.count)人")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .scale(scale: 0.4)).combined(with: .opacity),
                    removal:   .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
        .clipped()
    }

    // MARK: - 選択肢チップ行

    private var choiceRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // ＋ ボタン（全種類追加済みなら非表示）
                    let available = AnswerChoice.allCases.filter { $0 != .freeText }
                    if choices.count < available.count {
                        Button { isShowingChoiceMenu = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 36, height: 36)
                                .background(Color(UIColor.tertiarySystemFill))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color(UIColor.separator), lineWidth: 1))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(choices) { choice in
                        choiceChip(choice)
                    }
                }
                .padding(.vertical, 4)
            }

            // リマインダーボタン
            Button { isShowingReminderMenu = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 20))
                        .foregroundStyle(reminderSeconds != nil ? Color.orange : .secondary)
                        .padding(10)
                    if reminderSeconds != nil {
                        Circle().fill(Color.orange).frame(width: 7, height: 7).offset(x: 2, y: 2)
                    }
                }
            }
            .confirmationDialog("自動リマインドを設定", isPresented: $isShowingReminderMenu, titleVisibility: .visible) {
                if reminderSeconds != nil {
                    Button("オフにする", role: .destructive) { reminderSeconds = nil }
                }
                Button("1時間後")  { reminderSeconds = 3600 }
                Button("3時間後")  { reminderSeconds = 10800 }
                Button("6時間後")  { reminderSeconds = 21600 }
                Button("12時間後") { reminderSeconds = 43200 }
                Button("キャンセル", role: .cancel) {}
            }
        }
        .confirmationDialog("選択肢を追加", isPresented: $isShowingChoiceMenu, titleVisibility: .visible) {
            let available = AnswerChoice.allCases.filter { c in c != .freeText && !choices.contains { $0.id == c.id } }
            ForEach(available) { choice in
                let isPro = (choice == .star || choice == .emoji)
                Button(choice.menuLabel + (isPro && !purchaseStore.isPro ? " 👑" : "")) {
                    if isPro && !purchaseStore.isPro { showPaywall = true }
                    else { choices.append(choice) }
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func choiceChip(_ choice: AnswerChoice) -> some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Image(systemName: choice.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(choice.tintColor)
                if let label = choice.shortLabel {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(choice.tintColor.opacity(0.18))
            .clipShape(Capsule())

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    choices.removeAll { $0.id == choice.id }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .background(Color(UIColor.systemBackground).opacity(0.6), in: Circle())
            }
            .offset(x: 8, y: -8)
        }
        .padding(.top, 8)
        .padding(.trailing, 8)
    }

    // MARK: - 送信エリア（テンプレート＋送信）

    private var sendRow: some View {
        HStack {
            Spacer()

            // テンプレートボタン
            Button { showTemplates = true } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(UIColor.tertiarySystemFill))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // 送信ボタン（中央の主役）
            Button(action: handleSend) {
                ZStack {
                    Circle()
                        .fill(canSend ? Color.primary : Color(UIColor.tertiarySystemFill))
                        .frame(width: 72, height: 72)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(canSend ? Color(UIColor.systemBackground) : Color.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)

            Spacer()

            // バランス用（右側）
            Color.clear.frame(width: 44, height: 44)

            Spacer()
        }
    }

    // MARK: - 送信ロジック

    private func handleSend() {
        let trimmed = questionText.trimmingCharacters(in: .whitespaces)

        let stopNames: [String]
        if !selectedFriends.isEmpty {
            stopNames = selectedFriends.filter { friendStore.isStopTime($0) }.map(\.name)
        } else if let group = selectedGroup {
            stopNames = group.memberIds.compactMap { id in
                friendStore.friends.first { $0.id == id && friendStore.isStopTime($0) }?.name
            }
        } else {
            stopNames = []
        }

        guard stopNames.isEmpty else {
            stopTimeNames = stopNames.joined(separator: "、")
            showStopTimeAlert = true
            return
        }

        if !selectedFriends.isEmpty {
            questionStore.sendToIndividuals(text: trimmed, to: selectedFriends, choices: choices, reminderAfter: reminderSeconds)
            // Live Activity はローカルのみの友達（firebaseUID なし）の代理回答用。Firebase連携済みの友達は本人の端末で起動されるべき
            let targets = selectedFriends.filter { $0.firebaseUID.isEmpty }
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
        } else if let group = selectedGroup {
            questionStore.send(text: trimmed, to: group, friends: friendStore.friends, choices: choices, reminderAfter: reminderSeconds)
            let target = group
            Task { @MainActor in
                if let question = questionStore.questions.last {
                    // Live Activity はローカルのみのメンバー（firebaseUID なし）の代理回答用。Firebase連携済みメンバーは本人の端末で起動されるべき
                    for memberId in target.memberIds {
                        guard let friend = friendStore.friends.first(where: { $0.id == memberId }),
                              friend.firebaseUID.isEmpty else { continue }
                        ActivityManager.shared.start(
                            question:   question,
                            memberId:   memberId,
                            memberName: friend.name
                        )
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }
            }
        }

        questionText    = ""
        selectedFriends = []
        selectedGroup   = nil
        choices         = [.yes, .no]
        reminderSeconds = nil
        reviewManager.onQuestionSent()
    }

    // MARK: - テンプレート適用

    private func applyTemplate(_ template: QuestionTemplate) {
        questionText = template.text
        choices = template.choices.compactMap { AnswerChoice(rawValue: $0) }
        if choices.isEmpty { choices = [.yes, .no] }
        if let groupId = template.groupId {
            selectedGroup   = groupStore.groups.first { $0.id == groupId }
            selectedFriends = []
        } else {
            selectedFriends = template.friendIds.compactMap { id in
                friendStore.friends.first { $0.id == id }
            }
            selectedGroup = nil
        }
    }
}

// MARK: - Preview

#Preview {
    SendTabView()
        .environmentObject(QuestionStore())
        .environmentObject(FriendStore())
        .environmentObject(GroupStore())
        .environmentObject(ProfileStore())
        .environmentObject(PurchaseStore())
        .environmentObject(TemplateStore())
}

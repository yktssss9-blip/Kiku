import SwiftUI

// MARK: - QuestionComposerView

struct QuestionComposerView: View {
    var onSend: (String, [Friend]?, KikuGroup?, [AnswerChoice]) -> Void

    @EnvironmentObject private var profileStore:  ProfileStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var groupStore:    GroupStore
    @EnvironmentObject private var templateStore: TemplateStore

    @State private var questionText:    String     = ""
    @State private var selectedFriends: [Friend]   = []
    @State private var selectedGroup:   KikuGroup? = nil
    @State private var isShowingPicker:   Bool          = false

    // 回答選択肢（デフォルト: ○ ✕）
    @State private var choices:              [AnswerChoice] = [.yes, .no]
    @State private var isShowingChoiceMenu:  Bool           = false
    @State private var isShowingTemplates:   Bool           = false
    @State private var showStopTimeAlert:    Bool           = false
    @State private var stopTimeNames:        String         = ""
    @State private var pendingText:          String         = ""
    @State private var pendingFriends:       [Friend]?      = nil
    @State private var pendingGroup:         KikuGroup?     = nil
    @State private var pendingChoices:       [AnswerChoice] = []

    private var canSend: Bool {
        let hasText = !questionText.trimmingCharacters(in: .whitespaces).isEmpty
        return hasText && (!selectedFriends.isEmpty || selectedGroup != nil)
    }

    var body: some View {
        VStack(spacing: 0) {

            // ① 質問入力行
            HStack(alignment: .center, spacing: 12) {
                Group {
                    if let image = profileStore.profileImage {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Text(profileStore.emoji)
                            .font(.system(size: 28))
                    }
                }
                .frame(width: 42, height: 42)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(Circle())

                TextField("質問を送ろう…", text: $questionText, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 16)

            // ② 送信先アバター行
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {

                    // ＋ 追加ボタン
                    Button {
                        isShowingPicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 40, height: 40)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    // 選択済み友達
                    ForEach(selectedFriends) { friend in
                        ZStack(alignment: .topTrailing) {
                            ZStack(alignment: .bottomTrailing) {
                                Text(friend.emoji)
                                    .font(.system(size: 22))
                                    .frame(width: 40, height: 40)
                                    .background(friendStore.isStopTime(friend) ? Color.orange.opacity(0.15) : Color.blue.opacity(0.12))
                                    .clipShape(Circle())
                                if friendStore.isStopTime(friend) {
                                    Image(systemName: "pause.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.orange)
                                        .background(Color(UIColor.systemBackground), in: Circle())
                                        .offset(x: 4, y: 4)
                                }
                            }

                            Button {
                                selectedFriends.removeAll { $0.id == friend.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                                    .background(Color.gray, in: Circle())
                            }
                            .offset(x: 4, y: -4)
                        }
                    }

                    // 選択済みグループ
                    if let group = selectedGroup {
                        HStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                Text("👥")
                                    .font(.system(size: 22))
                                    .frame(width: 40, height: 40)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Circle())

                                Button {
                                    selectedGroup = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white)
                                        .background(Color.gray, in: Circle())
                                }
                                .offset(x: 4, y: -4)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("\(group.memberIds.count)人")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider()
                .padding(.horizontal, 16)

            // ③ ボトムバー: 回答選択肢チップ + 送信ボタン
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {

                        // ＋ ボタン（一番左・全種類追加済みなら非表示）
                        let availableChoices = AnswerChoice.allCases.filter { $0 != .freeText }
                        if choices.count < availableChoices.count {
                            Button {
                                isShowingChoiceMenu = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 36, height: 36)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        // 追加済み選択肢チップ（全て × で削除可能）
                        ForEach(choices) { choice in
                            choiceChip(choice)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.vertical, 12)
                }

                // テンプレートボタン
                Button {
                    isShowingTemplates = true
                } label: {
                    Image(systemName: "bookmark")
                        .font(.title2)
                        .foregroundStyle(Color.secondary)
                        .padding(10)
                }
                .padding(.trailing, 2)

                // 送信ボタン（右端固定）
                Button {
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
                    if stopNames.isEmpty {
                        onSend(trimmed, selectedFriends.isEmpty ? nil : selectedFriends, selectedGroup, choices)
                        resetComposer()
                    } else {
                        pendingText    = trimmed
                        pendingFriends = selectedFriends.isEmpty ? nil : selectedFriends
                        pendingGroup   = selectedGroup
                        pendingChoices = choices
                        stopTimeNames  = stopNames.joined(separator: "、")
                        showStopTimeAlert = true
                    }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Color.blue : Color.secondary)
                        .padding(10)
                        .background(
                            canSend ? Color.blue.opacity(0.1) : Color.clear,
                            in: Circle()
                        )
                }
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.15), value: canSend)
                .padding(.trailing, 12)
            }
            .confirmationDialog("選択肢を追加", isPresented: $isShowingChoiceMenu, titleVisibility: .visible) {
                ForEach(AnswerChoice.allCases.filter { c in c != .freeText && !choices.contains { $0.id == c.id } }) { choice in
                    Button(choice.menuLabel) {
                        choices.append(choice)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            }
        }
        .alert("Stop Time 中の人がいます", isPresented: $showStopTimeAlert) {
            Button("それでも送信する", role: .destructive) {
                onSend(pendingText, pendingFriends, pendingGroup, pendingChoices)
                resetComposer()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(stopTimeNames) は現在 Stop Time 中です。それでも送信しますか？")
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        .sheet(isPresented: $isShowingPicker) {
            DestinationPickerSheet(
                selectedFriends: $selectedFriends,
                selectedGroup:   $selectedGroup
            )
            .environmentObject(friendStore)
            .environmentObject(groupStore)
        }
        .sheet(isPresented: $isShowingTemplates) {
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
        }
    }

    private func resetComposer() {
        questionText    = ""
        selectedFriends = []
        selectedGroup   = nil
        choices         = [.yes, .no]
    }

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

    // MARK: - 選択肢チップ

    @ViewBuilder
    private func choiceChip(_ choice: AnswerChoice) -> some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 5) {
                Image(systemName: choice.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(choice.tintColor)
                if let label = choice.shortLabel {
                    Text(label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(choice.tintColor.opacity(0.12))
            .clipShape(Capsule())

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    choices.removeAll { $0.id == choice.id }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .background(Color.gray.opacity(0.8), in: Circle())
            }
            .offset(x: 6, y: -6)
        }
        .padding(.top, 6)
        .padding(.trailing, 6)
    }
}

// MARK: - DestinationPickerSheet（友達・グループ統合）

private struct DestinationPickerSheet: View {
    @Binding var selectedFriends: [Friend]
    @Binding var selectedGroup:   KikuGroup?

    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var groupStore:  GroupStore
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingGroupCreate = false
    @State private var searchText: String = ""

    private var filteredFriends: [Friend] {
        if searchText.isEmpty { return friendStore.friends }
        return friendStore.friends.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredGroups: [KikuGroup] {
        let sorted = groupStore.groups.sorted { $0.createdAt > $1.createdAt }
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                // ─── 友達セクション ───
                if !filteredFriends.isEmpty {
                    Section("友達") {
                        ForEach(filteredFriends) { friend in
                            let isSelected  = selectedFriends.contains { $0.id == friend.id }
                            let isStopTime  = friendStore.isStopTime(friend)
                            Button {
                                if isSelected {
                                    selectedFriends.removeAll { $0.id == friend.id }
                                } else {
                                    selectedFriends.append(friend)
                                    selectedGroup = nil
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(friend.emoji).font(.title2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.name).font(.body).foregroundStyle(.primary)
                                        if isStopTime {
                                            Label("Stop Time 中", systemImage: "pause.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                            .fontWeight(.semibold)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // ─── グループセクション ───
                if !filteredGroups.isEmpty || searchText.isEmpty {
                Section {
                    // グループ一覧
                    ForEach(filteredGroups) { group in
                        let isSelected = selectedGroup?.id == group.id
                        Button {
                            selectedGroup   = isSelected ? nil : group
                            selectedFriends = []   // 友達選択をクリア
                        } label: {
                            HStack(spacing: 12) {
                                Text("👥").font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name).font(.headline).foregroundStyle(.primary)
                                    Text("\(group.memberIds.count)人").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                        .fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // 新規作成ボタン
                    Button {
                        isShowingGroupCreate = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            Text("新しいグループを作成")
                                .font(.body)
                                .foregroundStyle(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("グループ")
                }
                }

                // ─── 空状態 ───
                if friendStore.friends.isEmpty && groupStore.groups.isEmpty {
                    ContentUnavailableView(
                        "送信先がありません",
                        systemImage: "person.badge.plus",
                        description: Text("ランキングタブから友達を追加してください")
                    )
                } else if !searchText.isEmpty && filteredFriends.isEmpty && filteredGroups.isEmpty {
                    ContentUnavailableView(
                        "「\(searchText)」は見つかりません",
                        systemImage: "magnifyingglass"
                    )
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "名前で検索")
            .task { await friendStore.fetchStopTimeStatuses() }
            .navigationTitle("送信先を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isShowingGroupCreate) {
                GroupCreateView()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    QuestionComposerView { text, friends, group, choices in
        print("送信: \(text), 選択肢: \(choices.map(\.id))")
    }
    .environmentObject(ProfileStore())
    .environmentObject(FriendStore())
    .environmentObject(GroupStore())
    .environmentObject(TemplateStore())
    .padding(20)
    .background(Color(UIColor.systemGroupedBackground))
}

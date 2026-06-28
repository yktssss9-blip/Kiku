import SwiftUI

struct TemplateAddSheet: View {
    @EnvironmentObject private var templateStore: TemplateStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var groupStore: GroupStore
    @Environment(\.dismiss) private var dismiss

    @State private var questionText = ""
    @State private var selectedFriendIds: Set<UUID> = []
    @State private var selectedGroupId: UUID? = nil
    @State private var choices: [AnswerChoice] = [.yes, .no]
    @State private var isShowingChoiceMenu = false

    private var canSave: Bool {
        !questionText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("質問文") {
                    TextField("例: 今夜ご飯食べる？", text: $questionText)
                        .autocorrectionDisabled()
                }

                Section("送信先（任意）") {
                    if friendStore.friends.isEmpty && groupStore.groups.isEmpty {
                        Text("友達タブから友達を追加してください")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        if !groupStore.groups.isEmpty {
                            DisclosureGroup("グループ") {
                                ForEach(groupStore.groups) { group in
                                    Button {
                                        if selectedGroupId == group.id {
                                            selectedGroupId = nil
                                        } else {
                                            selectedGroupId = group.id
                                            selectedFriendIds.removeAll()
                                        }
                                    } label: {
                                        HStack {
                                            Text("👥").font(.title3)
                                            Text(group.name).foregroundStyle(.primary)
                                            Spacer()
                                            if selectedGroupId == group.id {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.blue)
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !friendStore.friends.isEmpty {
                            DisclosureGroup("友達（\(selectedFriendIds.count)人選択中）") {
                                ForEach(friendStore.friends) { friend in
                                    Button {
                                        if selectedFriendIds.contains(friend.id) {
                                            selectedFriendIds.remove(friend.id)
                                        } else {
                                            selectedFriendIds.insert(friend.id)
                                            selectedGroupId = nil
                                        }
                                    } label: {
                                        HStack {
                                            UserAvatarView(emoji: friend.emoji, photoURL: friend.photoURL, size: 30)
                                            Text(friend.name).foregroundStyle(.primary)
                                            Spacer()
                                            if selectedFriendIds.contains(friend.id) {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.blue)
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                Section("回答の選択肢") {
                    ForEach(choices) { choice in
                        HStack(spacing: 8) {
                            Image(systemName: choice.icon)
                                .foregroundStyle(choice.tintColor)
                            Text(choice.menuLabel)
                        }
                    }
                    .onDelete { indexSet in
                        choices.remove(atOffsets: indexSet)
                    }

                    let available = AnswerChoice.allCases.filter { c in
                        c != .freeText && !choices.contains { $0.id == c.id }
                    }
                    if !available.isEmpty {
                        Button {
                            isShowingChoiceMenu = true
                        } label: {
                            Label("選択肢を追加", systemImage: "plus.circle")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .navigationTitle("テンプレートを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        templateStore.add(
                            text: questionText.trimmingCharacters(in: .whitespaces),
                            friendIds: Array(selectedFriendIds),
                            groupId: selectedGroupId,
                            choices: choices,
                            friends: friendStore.friends
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .confirmationDialog("選択肢を追加", isPresented: $isShowingChoiceMenu, titleVisibility: .visible) {
                let available = AnswerChoice.allCases.filter { c in
                    c != .freeText && !choices.contains { $0.id == c.id }
                }
                ForEach(available) { choice in
                    Button(choice.menuLabel) {
                        choices.append(choice)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }
}

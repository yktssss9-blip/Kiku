import SwiftUI

struct GroupEditView: View {
    let group: KikuGroup

    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var groupStore: GroupStore
    @Environment(\.dismiss) private var dismiss

    @State private var groupName: String
    @State private var selectedIds: Set<UUID>
    @State private var showDeleteAlert = false

    init(group: KikuGroup) {
        self.group = group
        _groupName = State(initialValue: group.name)
        _selectedIds = State(initialValue: Set(group.memberIds))
    }

    var canSave: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty
        && groupName.count <= 20
        && !selectedIds.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("グループ名") {
                    TextField("例: 家族・サークル・バイトなど", text: $groupName)
                        .autocorrectionDisabled()
                }

                Section("メンバーを選ぶ（\(selectedIds.count)人選択中）") {
                    if friendStore.friends.isEmpty {
                        Text("友達タブから友達を追加してください")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(friendStore.friends) { friend in
                            Button {
                                if selectedIds.contains(friend.id) {
                                    selectedIds.remove(friend.id)
                                } else {
                                    selectedIds.insert(friend.id)
                                }
                            } label: {
                                HStack {
                                    Text(friend.emoji).font(.title3)
                                    Text(friend.name).foregroundStyle(.primary)
                                    Spacer()
                                    if selectedIds.contains(friend.id) {
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

                Section {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("このグループを削除", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("グループを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存する") {
                        groupStore.update(
                            id: group.id,
                            name: groupName.trimmingCharacters(in: .whitespaces),
                            memberIds: Array(selectedIds)
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .alert("グループを削除しますか？", isPresented: $showDeleteAlert) {
                Button("削除", role: .destructive) {
                    groupStore.delete(id: group.id)
                    dismiss()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("「\(group.name)」とそのグループに送信した質問・回答データをすべて削除します。この操作は元に戻せません。")
            }
        }
    }
}

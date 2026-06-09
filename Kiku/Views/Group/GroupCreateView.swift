import SwiftUI

struct GroupCreateView: View {
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""
    @State private var selectedIds: Set<UUID> = []
    @State private var showPaywall = false

    var canCreate: Bool {
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
                                    UserAvatarView(emoji: friend.emoji, photoURL: friend.photoURL, size: 30)
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
            }
            .navigationTitle("グループを作成")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(purchaseStore)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("作成する") {
                        if !purchaseStore.isPro && groupStore.groups.count >= 3 {
                            showPaywall = true
                            return
                        }
                        groupStore.create(
                            name: groupName.trimmingCharacters(in: .whitespaces),
                            memberIds: Array(selectedIds),
                            friends: friendStore.friends
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate)
                }
            }
        }
    }
}

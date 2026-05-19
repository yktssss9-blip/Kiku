import SwiftUI

struct MemberListView: View {
    @EnvironmentObject private var friendStore: FriendStore
    @State private var isShowingAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if friendStore.friends.isEmpty {
                    emptyState
                } else {
                    friendList
                }
            }
            .navigationTitle("友達")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                MemberAddView { newFriend in
                    friendStore.add(newFriend)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("友達がいません")
                .font(.headline)
            Text("＋ボタンから追加してください")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var friendList: some View {
        List {
            ForEach(friendStore.friends) { friend in
                HStack(spacing: 12) {
                    Text(friend.emoji)
                        .font(.title2)
                    Text(friend.name)
                        .font(.body)
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: friendStore.delete)
        }
    }
}

#Preview {
    MemberListView()
        .environmentObject(FriendStore())
}

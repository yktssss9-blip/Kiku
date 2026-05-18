import SwiftUI

struct Friend: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var emoji: String
}

class FriendStore: ObservableObject {
    @Published var friends: [Friend] = [] {
        didSet { save() }
    }

    private let key = "kiku.friends"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Friend].self, from: data) {
            friends = decoded
        }
    }

    func add(_ friend: Friend) {
        friends.append(friend)
    }

    func delete(at offsets: IndexSet) {
        friends.remove(atOffsets: offsets)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(friends) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct MemberListView: View {
    @StateObject private var store = FriendStore()
    @State private var isShowingAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if store.friends.isEmpty {
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
                    store.add(newFriend)
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
            ForEach(store.friends) { friend in
                HStack(spacing: 12) {
                    Text(friend.emoji)
                        .font(.title2)
                    Text(friend.name)
                        .font(.body)
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: store.delete)
        }
    }
}

#Preview {
    MemberListView()
}

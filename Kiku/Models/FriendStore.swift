import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct Friend: Identifiable, Codable {
    var id: UUID = UUID()
    var firebaseUID: String = ""   // Firestoreユーザー（空 = 旧ローカルデータ）
    var name: String
    var emoji: String
}

// MARK: - Firestore検索結果

struct FirestoreUser {
    let uid: String
    let name: String
    let emoji: String
    let username: String
}

class FriendStore: ObservableObject {
    @Published var friends: [Friend] = [] {
        didSet { saveFriends() }
    }
    @Published var blockedIds: Set<UUID> = [] {
        didSet { saveBlocked() }
    }
    @Published var stopTimeActiveUIDs: Set<String> = []

    private let friendsKey = "kiku.friends"
    private let blockedKey = "kiku.blockedFriends"
    private let db = Firestore.firestore()

    init() {
        if let data = UserDefaults.standard.data(forKey: friendsKey),
           let decoded = try? JSONDecoder().decode([Friend].self, from: data) {
            friends = decoded
        }
        if let data = UserDefaults.standard.data(forKey: blockedKey),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            blockedIds = Set(decoded)
        }
    }

    func add(_ friend: Friend) {
        friends.append(friend)
    }

    func delete(at offsets: IndexSet) {
        friends.remove(atOffsets: offsets)
    }

    func delete(id: UUID) {
        friends.removeAll { $0.id == id }
        blockedIds.remove(id)
    }

    func friend(for id: UUID) -> Friend? {
        friends.first { $0.id == id }
    }

    func isBlocked(_ id: UUID) -> Bool {
        blockedIds.contains(id)
    }

    func block(_ id: UUID) {
        blockedIds.insert(id)
    }

    func unblock(_ id: UUID) {
        blockedIds.remove(id)
    }

    // MARK: - Stop Time

    func isStopTime(_ friend: Friend) -> Bool {
        guard !friend.firebaseUID.isEmpty else { return false }
        return stopTimeActiveUIDs.contains(friend.firebaseUID)
    }

    func fetchStopTimeStatuses() async {
        let uids = friends.compactMap { $0.firebaseUID.isEmpty ? nil : $0.firebaseUID }
        guard !uids.isEmpty else { return }
        var activeSet: Set<String> = []
        for uid in uids {
            if let doc = try? await db.collection("users").document(uid).getDocument(),
               let active = doc.data()?["stopTimeActive"] as? Bool, active {
                activeSet.insert(uid)
            }
        }
        await MainActor.run { stopTimeActiveUIDs = activeSet }
    }

    // MARK: - Firestoreユーザー検索

    /// ユーザー名でFirestoreを検索してユーザー情報を返す
    func searchUser(username: String) async throws -> FirestoreUser? {
        let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // /usernames/{username} からUIDを取得
        let usernameDoc = try await db.collection("usernames").document(trimmed).getDocument()
        guard let uid = usernameDoc.data()?["uid"] as? String else { return nil }

        // 自分自身は追加できない
        if uid == Auth.auth().currentUser?.uid { return nil }

        // /users/{uid} からプロフィールを取得
        let userDoc = try await db.collection("users").document(uid).getDocument()
        guard let data = userDoc.data(),
              let name = data["name"] as? String else { return nil }

        let emoji = data["emoji"] as? String ?? "👤"
        return FirestoreUser(uid: uid, name: name, emoji: emoji, username: trimmed)
    }

    // MARK: - 永続化

    private func saveFriends() {
        if let data = try? JSONEncoder().encode(friends) {
            UserDefaults.standard.set(data, forKey: friendsKey)
        }
    }

    private func saveBlocked() {
        if let data = try? JSONEncoder().encode(Array(blockedIds)) {
            UserDefaults.standard.set(data, forKey: blockedKey)
        }
    }
}

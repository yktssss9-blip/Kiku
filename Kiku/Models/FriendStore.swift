import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - FriendRequest（受信）

struct FriendRequest: Identifiable {
    let id: String
    let fromUID: String
    let fromName: String
    let fromEmoji: String
    let fromUsername: String
    let fromPhotoURL: String?
}

// MARK: - SentFriendRequest（送信済み）

struct SentFriendRequest: Identifiable {
    let id: String          // Firestore document ID
    let toUID: String
    let toName: String
    let toEmoji: String
    let toUsername: String
    let toPhotoURL: String?
    let status: String      // "pending" | "accepted" | "declined"
    let createdAt: Date
}

struct Friend: Identifiable, Codable {
    var id: UUID = UUID()
    var firebaseUID: String = ""   // Firestoreユーザー（空 = 旧ローカルデータ）
    var name: String
    var emoji: String
    var username: String = ""
    var photoURL: String? = nil
    var activeHourStart: Int? = nil
    var activeHourEnd: Int?   = nil
}

// MARK: - Firestore検索結果

struct FirestoreUser: Identifiable {
    var id: String { uid }
    let uid: String
    let name: String
    let emoji: String
    let photoURL: String?
    let username: String
    let activeHourStart: Int?
    let activeHourEnd: Int?
}

class FriendStore: ObservableObject {
    @Published var friends: [Friend] = [] {
        didSet { saveFriends() }
    }
    @Published var blockedIds: Set<UUID> = [] {
        didSet { saveBlocked() }
    }
    @Published var stopTimeActiveUIDs: Set<String> = []
    @Published var proUIDs: Set<String> = []
    @Published var pendingRequests: [FriendRequest] = []
    @Published var sentRequests: [SentFriendRequest] = []

    var onReceivedRequest: ((FriendRequest) -> Void)? = nil

    private let friendsKey = "kiku.friends"
    private let blockedKey = "kiku.blockedFriends"
    private let db = Firestore.firestore()
    private var requestsListener: ListenerRegistration?
    private var sentRequestsListener: ListenerRegistration?

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
        for chunk in stride(from: 0, to: uids.count, by: 30).map({ Array(uids[$0..<min($0+30, uids.count)]) }) {
            if let snapshot = try? await db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk).getDocuments() {
                for doc in snapshot.documents {
                    if doc.data()["stopTimeActive"] as? Bool == true {
                        activeSet.insert(doc.documentID)
                    }
                }
            }
        }
        await MainActor.run { stopTimeActiveUIDs = activeSet }
    }

    /// 友達がProプラン加入済みか（支配者称号の解放判定に使用）
    func isPro(_ friend: Friend) -> Bool {
        guard !friend.firebaseUID.isEmpty else { return false }
        return proUIDs.contains(friend.firebaseUID)
    }

    func fetchProStatuses() async {
        let uids = friends.compactMap { $0.firebaseUID.isEmpty ? nil : $0.firebaseUID }
        guard !uids.isEmpty else { return }
        var proSet: Set<String> = []
        for chunk in stride(from: 0, to: uids.count, by: 30).map({ Array(uids[$0..<min($0+30, uids.count)]) }) {
            if let snapshot = try? await db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk).getDocuments() {
                for doc in snapshot.documents {
                    if doc.data()["isPro"] as? Bool == true {
                        proSet.insert(doc.documentID)
                    }
                }
            }
        }
        await MainActor.run { proUIDs = proSet }
    }

    // MARK: - プロフィール更新

    func refreshFriendProfiles() async {
        let uids = friends.compactMap { $0.firebaseUID.isEmpty ? nil : $0.firebaseUID }
        guard !uids.isEmpty else { return }
        var updates: [(UUID, String, String, String?)] = []
        for chunk in stride(from: 0, to: uids.count, by: 30).map({ Array(uids[$0..<min($0+30, uids.count)]) }) {
            guard let snapshot = try? await db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk).getDocuments() else { continue }
            for doc in snapshot.documents {
                let data = doc.data()
                guard let idx = friends.firstIndex(where: { $0.firebaseUID == doc.documentID }) else { continue }
                let name     = data["name"]     as? String ?? friends[idx].name
                let emoji    = data["emoji"]    as? String ?? friends[idx].emoji
                let photoURL = data["photoURL"] as? String
                updates.append((friends[idx].id, name, emoji, photoURL))
            }
        }
        await MainActor.run {
            for (id, name, emoji, photoURL) in updates {
                guard let i = friends.firstIndex(where: { $0.id == id }) else { continue }
                friends[i].name     = name
                friends[i].emoji    = emoji
                friends[i].photoURL = photoURL
            }
        }
    }

    // MARK: - 友達申請

    func startListeningRequests(forUID uid: String) {
        // 受信した申請（pending のみ）
        requestsListener = db.collection("friendRequests")
            .whereField("toUID", isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                let requests = docs.compactMap { doc -> FriendRequest? in
                    let data = doc.data()
                    guard let fromUID  = data["fromUID"]  as? String,
                          let fromName = data["fromName"] as? String else { return nil }
                    return FriendRequest(
                        id:           doc.documentID,
                        fromUID:      fromUID,
                        fromName:     fromName,
                        fromEmoji:    data["fromEmoji"]    as? String ?? "👤",
                        fromUsername: data["fromUsername"] as? String ?? "",
                        fromPhotoURL: data["fromPhotoURL"] as? String
                    )
                }
                DispatchQueue.main.async {
                    let prev = Set(self.pendingRequests.map(\.id))
                    self.pendingRequests = requests
                    // 新着申請のみコールバック（初回ロード除外: prevが空の場合は無視）
                    if !prev.isEmpty {
                        for req in requests where !prev.contains(req.id) {
                            self.onReceivedRequest?(req)
                        }
                    }
                }
            }

        // 自分が送った申請（全ステータス）— 承認時は友達自動追加も行う
        sentRequestsListener = db.collection("friendRequests")
            .whereField("fromUID", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                let sent = docs.compactMap { doc -> SentFriendRequest? in
                    let data = doc.data()
                    guard let toUID   = data["toUID"]   as? String,
                          let toName  = data["toName"]  as? String,
                          let status  = data["status"]  as? String else { return nil }
                    let ts = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    return SentFriendRequest(
                        id:          doc.documentID,
                        toUID:       toUID,
                        toName:      toName,
                        toEmoji:     data["toEmoji"]     as? String ?? "👤",
                        toUsername:  data["toUsername"]  as? String ?? "",
                        toPhotoURL:  data["toPhotoURL"]  as? String,
                        status:      status,
                        createdAt:   ts
                    )
                }
                DispatchQueue.main.async {
                    self.sentRequests = sent.sorted { $0.createdAt > $1.createdAt }
                    // 承認されたら友達自動追加
                    for req in sent where req.status == "accepted" {
                        if !self.friends.contains(where: { $0.firebaseUID == req.toUID }) {
                            self.friends.append(Friend(
                                firebaseUID: req.toUID,
                                name:        req.toName,
                                emoji:       req.toEmoji,
                                username:    req.toUsername,
                                photoURL:    req.toPhotoURL
                            ))
                        }
                    }
                }
            }
    }

    func stopListeningRequests() {
        requestsListener?.remove()
        sentRequestsListener?.remove()
        requestsListener = nil
        sentRequestsListener = nil
    }

    func refresh(forUID uid: String) async {
        stopListeningRequests()
        startListeningRequests(forUID: uid)
        await refreshFriendProfiles()
    }

    func sendFriendRequest(
        to user: FirestoreUser,
        fromName: String,
        fromEmoji: String,
        fromUsername: String,
        fromPhotoURL: String?
    ) async throws {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        let existing = try await db.collection("friendRequests")
            .whereField("fromUID", isEqualTo: myUID)
            .whereField("toUID", isEqualTo: user.uid)
            .whereField("status", isEqualTo: "pending")
            .getDocuments()
        guard existing.documents.isEmpty else { return }

        var data: [String: Any] = [
            "fromUID":      myUID,
            "fromName":     fromName,
            "fromEmoji":    fromEmoji,
            "fromUsername": fromUsername,
            "toUID":        user.uid,
            "toName":       user.name,
            "toEmoji":      user.emoji,
            "toUsername":   user.username,
            "status":       "pending",
            "createdAt":    FieldValue.serverTimestamp()
        ]
        if let url = fromPhotoURL { data["fromPhotoURL"] = url }
        if let url = user.photoURL { data["toPhotoURL"] = url }
        try await db.collection("friendRequests").document().setData(data)
    }

    func acceptFriendRequest(requestId: String, fromUID: String, fromName: String, fromEmoji: String, fromPhotoURL: String?, fromUsername: String = "") async {
        do {
            try await db.collection("friendRequests").document(requestId).updateData(["status": "accepted"])
            let friend = Friend(firebaseUID: fromUID, name: fromName, emoji: fromEmoji, username: fromUsername, photoURL: fromPhotoURL)
            await MainActor.run {
                if !friends.contains(where: { $0.firebaseUID == fromUID }) {
                    friends.append(friend)
                }
            }
        } catch {
            print("[FriendStore] acceptFriendRequest error: \(error)")
        }
    }

    func declineFriendRequest(requestId: String) async {
        try? await db.collection("friendRequests").document(requestId).updateData(["status": "declined"])
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

        let emoji           = data["emoji"]           as? String ?? "👤"
        let photoURL        = data["photoURL"]        as? String
        let activeHourStart = data["activeHourStart"] as? Int
        let activeHourEnd   = data["activeHourEnd"]   as? Int
        return FirestoreUser(uid: uid, name: name, emoji: emoji, photoURL: photoURL,
                             username: trimmed, activeHourStart: activeHourStart,
                             activeHourEnd: activeHourEnd)
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

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct KikuGroup: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var memberIds: [UUID]
    var createdAt: Date = Date()
    var createdBy: String = ""
    var memberUIDs: [String] = []

    enum CodingKeys: String, CodingKey {
        case id, name, memberIds, createdAt, createdBy, memberUIDs
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,     forKey: .id)
        name       = try c.decode(String.self,   forKey: .name)
        memberIds  = try c.decode([UUID].self,   forKey: .memberIds)
        createdAt  = try c.decodeIfPresent(Date.self,     forKey: .createdAt)  ?? Date()
        createdBy  = try c.decodeIfPresent(String.self,   forKey: .createdBy)  ?? ""
        memberUIDs = try c.decodeIfPresent([String].self, forKey: .memberUIDs) ?? []
    }
    init(id: UUID = UUID(), name: String, memberIds: [UUID], createdAt: Date = Date(),
         createdBy: String = "", memberUIDs: [String] = []) {
        self.id = id; self.name = name; self.memberIds = memberIds
        self.createdAt = createdAt; self.createdBy = createdBy; self.memberUIDs = memberUIDs
    }
}

class GroupStore: ObservableObject {
    @Published var groups: [KikuGroup] = [] {
        didSet {
            if !isUpdatingFromFirestore { save() }
        }
    }

    private let key = "kiku.groups"
    private let db  = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var isUpdatingFromFirestore = false

    /// UID ⇔ ローカル Friend UUID 変換用（KikuApp から注入）
    weak var friendStore: FriendStore?

    /// グループ削除時に呼ばれるコールバック（削除された groupId を渡す）
    var onGroupDeleted: ((UUID) -> Void)?

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([KikuGroup].self, from: data) {
            groups = decoded
        }
    }

    // MARK: - Firestore リスナー

    func startListening(forUID uid: String) {
        stopListening()
        migrateLocalGroupsIfNeeded(uid: uid)
        listener = db.collection("groups")
            .whereField("createdBy", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                self.mergeFromFirestore(docs)
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// 旧ローカルデータ（createdBy が空）を初回ログイン時に Firestore へアップロード
    private func migrateLocalGroupsIfNeeded(uid: String) {
        let targets = groups.filter { $0.createdBy.isEmpty }
        guard !targets.isEmpty else { return }
        for var group in targets {
            group.createdBy  = uid
            group.memberUIDs = uids(for: group.memberIds)
            if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                groups[idx] = group
            }
            saveGroupToFirestore(group)
        }
    }

    /// Firestoreから取得したグループをローカルにマージ
    private func mergeFromFirestore(_ docs: [QueryDocumentSnapshot]) {
        var merged = self.groups
        for doc in docs {
            guard let g = groupFromFirestore(doc) else { continue }
            if let idx = merged.firstIndex(where: { $0.id == g.id }) {
                merged[idx] = g
            } else {
                merged.append(g)
            }
        }
        let remoteIds = Set(docs.compactMap { UUID(uuidString: $0.documentID) })
        merged.removeAll { !$0.createdBy.isEmpty && !remoteIds.contains($0.id) }

        DispatchQueue.main.async {
            self.isUpdatingFromFirestore = true
            self.groups = merged
            self.isUpdatingFromFirestore = false
        }
    }

    // MARK: - CRUD

    func create(name: String, memberIds: [UUID], friends: [Friend] = []) {
        let group = KikuGroup(name: name, memberIds: memberIds,
                              createdBy: Auth.auth().currentUser?.uid ?? "",
                              memberUIDs: uids(for: memberIds, friends: friends))
        groups.append(group)
        saveGroupToFirestore(group)
    }

    func update(id: UUID, name: String, memberIds: [UUID], friends: [Friend] = []) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name       = name
        groups[index].memberIds  = memberIds
        groups[index].memberUIDs = uids(for: memberIds, friends: friends)

        let group = groups[index]
        db.collection("groups").document(group.id.uuidString).updateData([
            "name":       group.name,
            "memberUIDs": group.memberUIDs
        ])
    }

    /// スワイプ削除用（IndexSet 版）
    func delete(at offsets: IndexSet) {
        let deletedIds = offsets.map { groups[$0].id }
        groups.remove(atOffsets: offsets)
        for id in deletedIds {
            db.collection("groups").document(id.uuidString).delete()
            onGroupDeleted?(id)
        }
    }

    /// ID 指定削除（EditView の削除ボタン用）
    func delete(id: UUID) {
        groups.removeAll { $0.id == id }
        db.collection("groups").document(id.uuidString).delete()
        onGroupDeleted?(id)
    }

    // MARK: - UID ⇔ ローカル UUID 変換

    private func uids(for memberIds: [UUID], friends: [Friend]? = nil) -> [String] {
        let list = friends ?? friendStore?.friends ?? []
        return memberIds.compactMap { id in
            let uid = list.first { $0.id == id }?.firebaseUID
            return (uid?.isEmpty == false) ? uid : nil
        }
    }

    private func memberIds(for memberUIDs: [String]) -> [UUID] {
        guard let friends = friendStore?.friends else { return [] }
        return memberUIDs.compactMap { uid in
            friends.first { $0.firebaseUID == uid }?.id
        }
    }

    // MARK: - Firestore データ変換

    private func saveGroupToFirestore(_ group: KikuGroup) {
        guard !group.createdBy.isEmpty else { return }
        db.collection("groups").document(group.id.uuidString).setData([
            "name":       group.name,
            "memberUIDs": group.memberUIDs,
            "createdAt":  Timestamp(date: group.createdAt),
            "createdBy":  group.createdBy
        ])
    }

    private func groupFromFirestore(_ doc: QueryDocumentSnapshot) -> KikuGroup? {
        guard let id = UUID(uuidString: doc.documentID) else { return nil }
        let data = doc.data()
        guard let name = data["name"] as? String else { return nil }

        let memberUIDs = data["memberUIDs"] as? [String] ?? []
        let createdAt  = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let createdBy  = data["createdBy"] as? String ?? ""

        return KikuGroup(id: id, name: name, memberIds: memberIds(for: memberUIDs),
                         createdAt: createdAt, createdBy: createdBy, memberUIDs: memberUIDs)
    }

    // MARK: - ローカル永続化

    private func save() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

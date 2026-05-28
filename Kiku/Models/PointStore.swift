import Foundation
import FirebaseFirestore
import FirebaseAuth

class PointStore: ObservableObject {
    @Published var records: [PointRecord] = [] {
        didSet {
            if !isUpdatingFromFirestore { save() }
        }
    }

    private let key = "kiku.points"
    private let db  = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var isUpdatingFromFirestore = false

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([PointRecord].self, from: data) {
            records = decoded
        }
    }

    // MARK: - Firestore リスナー

    func startListening(forUID uid: String) {
        stopListening()
        // 直近7日分のみ取得
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        listener = db.collection("users").document(uid)
            .collection("points")
            .whereField("earnedAt", isGreaterThan: Timestamp(date: cutoff))
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                self.mergeFromFirestore(docs)
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    private func mergeFromFirestore(_ docs: [QueryDocumentSnapshot]) {
        var merged = self.records
        for doc in docs {
            guard let record = recordFromFirestore(doc) else { continue }
            if !merged.contains(where: { $0.id == record.id }) {
                merged.append(record)
            }
        }
        DispatchQueue.main.async {
            self.isUpdatingFromFirestore = true
            self.records = merged
            self.isUpdatingFromFirestore = false
        }
    }

    // MARK: - 集計（直近7日間のみ有効）

    private static let retentionDays: Double = 7

    private var activeRecords: [PointRecord] {
        let cutoff = Date().addingTimeInterval(-Self.retentionDays * 24 * 60 * 60)
        return records.filter { $0.earnedAt >= cutoff }
    }

    func total(for memberId: UUID) -> Int {
        activeRecords.filter { $0.memberId == memberId }.reduce(0) { $0 + $1.points }
    }

    func history(for memberId: UUID) -> [PointRecord] {
        activeRecords.filter { $0.memberId == memberId }
                     .sorted { $0.earnedAt > $1.earnedAt }
    }

    func title(rank: Int, outOf total: Int) -> PointTitle {
        PointTitle(rank: rank, outOf: total)
    }

    // MARK: - 追加

    func add(questionId: UUID, memberId: UUID, questionText: String, elapsed: TimeInterval) {
        let tier = PointTier.tier(for: elapsed)
        let record = PointRecord(
            questionId:   questionId,
            memberId:     memberId,
            questionText: questionText,
            tier:         tier
        )
        records.append(record)
        saveRecordToFirestore(record)
    }

    func addSenderBonus(questionId: UUID, senderMemberId: UUID, questionText: String, elapsed: TimeInterval) {
        let tier: PointTier
        switch PointTier.tier(for: elapsed) {
        case .fast:                           tier = .senderFast
        case .normal:                         tier = .senderNormal
        case .late, .senderFast, .senderNormal: return
        }
        let record = PointRecord(
            questionId:   questionId,
            memberId:     senderMemberId,
            questionText: questionText,
            tier:         tier
        )
        records.append(record)
        saveRecordToFirestore(record)
    }

    // MARK: - リセット

    func reset() {
        records = []
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Firestore データ変換

    private func saveRecordToFirestore(_ record: PointRecord) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "questionId":   record.questionId.uuidString,
            "memberId":     record.memberId.uuidString,
            "questionText": record.questionText,
            "tier":         record.tier.rawValue,
            "earnedAt":     Timestamp(date: record.earnedAt)
        ]
        db.collection("users").document(uid)
            .collection("points").document(record.id.uuidString)
            .setData(data)
    }

    private func recordFromFirestore(_ doc: QueryDocumentSnapshot) -> PointRecord? {
        let data = doc.data()
        guard let id           = UUID(uuidString: doc.documentID),
              let questionIdStr = data["questionId"] as? String,
              let questionId   = UUID(uuidString: questionIdStr),
              let memberIdStr  = data["memberId"] as? String,
              let memberId     = UUID(uuidString: memberIdStr),
              let questionText = data["questionText"] as? String,
              let tierRaw      = data["tier"] as? String,
              let tier         = PointTier(rawValue: tierRaw),
              let earnedAt     = (data["earnedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        return PointRecord(id: id, questionId: questionId, memberId: memberId,
                           questionText: questionText, tier: tier, earnedAt: earnedAt)
    }

    // MARK: - ローカル永続化

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

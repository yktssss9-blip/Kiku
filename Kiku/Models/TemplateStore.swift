import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - ScheduleConfig

struct ScheduleConfig: Codable, Equatable {
    enum RepeatType: String, Codable {
        case daily
        case weekly
    }

    var isEnabled: Bool = false
    var repeatType: RepeatType = .daily
    var hour: Int = 9
    var minute: Int = 0
    var weekdays: [Int] = []   // 1=日, 2=月, ..., 7=土（weekly時のみ）
    var nextSendAt: Date? = nil // Cloud Functions がこれを監視してトリガー

    var timeDate: Date {
        get {
            Calendar.current.date(
                bySettingHour: hour, minute: minute, second: 0, of: Date()
            ) ?? Date()
        }
        set {
            hour   = Calendar.current.component(.hour,   from: newValue)
            minute = Calendar.current.component(.minute, from: newValue)
        }
    }

    var displayLabel: String {
        let hm = String(format: "%02d:%02d", hour, minute)
        switch repeatType {
        case .daily:
            return "毎日 \(hm)"
        case .weekly:
            let dayNames = ["日", "月", "火", "水", "木", "金", "土"]
            let days = weekdays.sorted().compactMap { i in
                (i >= 1 && i <= 7) ? dayNames[i - 1] : nil
            }.joined(separator: "・")
            return days.isEmpty ? "曜日未設定" : "毎週\(days) \(hm)"
        }
    }

    // MARK: Firestore 変換

    func toFirestore() -> [String: Any] {
        var dict: [String: Any] = [
            "isEnabled":  isEnabled,
            "repeatType": repeatType.rawValue,
            "hour":       hour,
            "minute":     minute,
            "weekdays":   weekdays,
        ]
        if let next = nextSendAt {
            dict["nextSendAt"] = Timestamp(date: next)
        }
        return dict
    }

    static func from(_ dict: [String: Any]) -> ScheduleConfig {
        var c = ScheduleConfig()
        c.isEnabled  = dict["isEnabled"]  as? Bool   ?? false
        c.repeatType = RepeatType(rawValue: dict["repeatType"] as? String ?? "") ?? .daily
        c.hour       = dict["hour"]       as? Int    ?? 9
        c.minute     = dict["minute"]     as? Int    ?? 0
        c.weekdays   = dict["weekdays"]   as? [Int]  ?? []
        if let ts = dict["nextSendAt"] as? Timestamp {
            c.nextSendAt = ts.dateValue()
        }
        return c
    }
}

// MARK: - QuestionTemplate

struct QuestionTemplate: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var friendIds: [UUID] = []
    var groupId: UUID? = nil
    var choices: [String] = ["yes", "no"]
    var createdAt: Date = Date()
    var schedule: ScheduleConfig = ScheduleConfig()
}

// MARK: - TemplateStore

class TemplateStore: ObservableObject {
    @Published var templates: [QuestionTemplate] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var isUpdatingFromFirestore = false

    init() {
        loadFromUserDefaults()
    }

    deinit { listener?.remove() }

    // MARK: - リスナー

    func startListening(forUID uid: String) {
        listener?.remove()
        listener = db.collection("users").document(uid)
            .collection("templates")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let docs = snapshot?.documents, error == nil else { return }
                isUpdatingFromFirestore = true
                templates = docs.compactMap { doc -> QuestionTemplate? in
                    let d = doc.data()
                    guard let text = d["text"] as? String else { return nil }
                    var t = QuestionTemplate(text: text)
                    t.id        = UUID(uuidString: doc.documentID) ?? UUID()
                    t.friendIds = (d["friendIds"] as? [String] ?? []).compactMap { UUID(uuidString: $0) }
                    t.groupId   = (d["groupId"] as? String).flatMap { UUID(uuidString: $0) }
                    t.choices   = d["choices"] as? [String] ?? ["yes", "no"]
                    if let ts = d["createdAt"] as? Timestamp { t.createdAt = ts.dateValue() }
                    if let sd = d["schedule"] as? [String: Any] { t.schedule = ScheduleConfig.from(sd) }
                    return t
                }
                isUpdatingFromFirestore = false
                saveToUserDefaults()
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func refresh(forUID uid: String) async {
        stopListening()
        startListening(forUID: uid)
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    // MARK: - CRUD

    func add(text: String, friendIds: [UUID], groupId: UUID?, choices: [AnswerChoice], friends: [Friend] = []) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let template = QuestionTemplate(
            text:      text,
            friendIds: friendIds,
            groupId:   groupId,
            choices:   choices.map(\.rawValue)
        )
        templates.insert(template, at: 0)
        saveToFirestore(template, uid: uid, friends: friends)
        saveToUserDefaults()
    }

    func updateSchedule(id: UUID, schedule: ScheduleConfig, friends: [Friend] = []) {
        guard let uid = Auth.auth().currentUser?.uid,
              let idx = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[idx].schedule = schedule
        saveToFirestore(templates[idx], uid: uid, friends: friends)
        saveToUserDefaults()
    }

    func delete(id: UUID) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        templates.removeAll { $0.id == id }
        db.collection("users").document(uid)
            .collection("templates").document(id.uuidString).delete()
        saveToUserDefaults()
    }

    // MARK: - Firestore 書き込み

    private func saveToFirestore(_ template: QuestionTemplate, uid: String, friends: [Friend] = []) {
        var data: [String: Any] = [
            "text":      template.text,
            "friendIds": template.friendIds.map(\.uuidString),
            "choices":   template.choices,
            "createdAt": Timestamp(date: template.createdAt),
            "schedule":  template.schedule.toFirestore(),
        ]
        if let gid = template.groupId { data["groupId"] = gid.uuidString }

        // Cloud Functions が自動送信時に質問の宛先を解決できるよう、
        // QuestionStore.firestoreData と同じ形式で Friend → Firebase UID の対応を保存する
        let targetFriends = friends.filter { f in template.friendIds.contains(f.id) }
        let memberNamesDict = targetFriends
            .reduce(into: [String: Any]()) { $0[$1.id.uuidString] = $1.name }
        if !memberNamesDict.isEmpty { data["memberNames"] = memberNamesDict }

        let recipientFriends = targetFriends.filter { !$0.firebaseUID.isEmpty }
        let recipientUIDs = recipientFriends.map(\.firebaseUID)
        if !recipientUIDs.isEmpty { data["recipientUIDs"] = recipientUIDs }

        let recipientMemberMap = recipientFriends
            .reduce(into: [String: Any]()) { $0[$1.firebaseUID] = $1.id.uuidString }
        if !recipientMemberMap.isEmpty { data["recipientMemberMap"] = recipientMemberMap }

        db.collection("users").document(uid)
            .collection("templates").document(template.id.uuidString)
            .setData(data, merge: true)
    }

    // MARK: - ローカルキャッシュ

    private let cacheKey = "kiku.templates"

    private func saveToUserDefaults() {
        guard !isUpdatingFromFirestore else { return }
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([QuestionTemplate].self, from: data) {
            templates = decoded
        }
    }
}

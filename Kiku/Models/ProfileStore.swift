import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Icon Mode

enum IconMode: String {
    case emoji = "emoji"
    case photo = "photo"
}

class ProfileStore: ObservableObject {
    private static let appGroup = UserDefaults(suiteName: "group.com.yukichi.kiku")
    private let db = Firestore.firestore()

    @Published var name: String {
        didSet {
            UserDefaults.standard.set(name, forKey: "kiku.profile.name")
            Self.appGroup?.set(name, forKey: "kiku.profile.name")
            saveProfileToFirestore()
        }
    }
    @Published var emoji: String {
        didSet {
            UserDefaults.standard.set(emoji, forKey: "kiku.profile.emoji")
            Self.appGroup?.set(emoji, forKey: "kiku.profile.emoji")
            saveProfileToFirestore()
        }
    }
    @Published var photoData: Data? {
        didSet {
            UserDefaults.standard.set(photoData, forKey: "kiku.profile.photo")
            Self.appGroup?.set(photoData, forKey: "kiku.profile.photo")
        }
    }
    @Published var iconMode: IconMode {
        didSet {
            UserDefaults.standard.set(iconMode.rawValue, forKey: "kiku.profile.iconMode")
            Self.appGroup?.set(iconMode.rawValue, forKey: "kiku.profile.iconMode")
        }
    }
    @Published var username: String {
        didSet {
            UserDefaults.standard.set(username, forKey: "kiku.profile.username")
        }
    }
    @Published var isStopTimeActive: Bool {
        didSet {
            UserDefaults.standard.set(isStopTimeActive, forKey: "kiku.profile.stopTimeActive")
            saveProfileToFirestore()
        }
    }
    @Published var activeHourStart: Int {
        didSet {
            UserDefaults.standard.set(activeHourStart, forKey: "kiku.profile.activeHourStart")
            saveProfileToFirestore()
        }
    }
    @Published var activeHourEnd: Int {
        didSet {
            UserDefaults.standard.set(activeHourEnd, forKey: "kiku.profile.activeHourEnd")
            saveProfileToFirestore()
        }
    }

    // 返信しやすい時間帯プリセット（end:24 = 深夜0時）
    static let activeHourPresets: [(label: String, emoji: String, start: Int, end: Int)] = [
        ("朝早め", "🌅", 6,  9),
        ("朝",    "☀️", 9,  12),
        ("昼",    "🌤", 12, 17),
        ("夕方",  "🌇", 17, 21),
        ("夜",    "🌙", 21, 24),
    ]

    /// 自分を識別する固定 UUID（初回起動時に生成・永続化）
    let myId: UUID

    var profileImage: Image? {
        guard iconMode == .photo,
              let data = photoData,
              let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }

    var isSetupComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init() {
        self.name      = UserDefaults.standard.string(forKey: "kiku.profile.name")     ?? ""
        self.emoji     = UserDefaults.standard.string(forKey: "kiku.profile.emoji")    ?? "👤"
        self.photoData = UserDefaults.standard.data(forKey: "kiku.profile.photo")
        self.username  = UserDefaults.standard.string(forKey: "kiku.profile.username") ?? ""

        let savedMode = UserDefaults.standard.string(forKey: "kiku.profile.iconMode") ?? ""
        let hasPhoto  = UserDefaults.standard.data(forKey: "kiku.profile.photo") != nil
        self.iconMode = IconMode(rawValue: savedMode) ?? (hasPhoto ? .photo : .emoji)
        self.isStopTimeActive  = UserDefaults.standard.bool(forKey: "kiku.profile.stopTimeActive")
        self.activeHourStart   = UserDefaults.standard.object(forKey: "kiku.profile.activeHourStart") as? Int ?? 9
        self.activeHourEnd     = UserDefaults.standard.object(forKey: "kiku.profile.activeHourEnd")   as? Int ?? 12

        if let saved = UserDefaults.standard.string(forKey: "kiku.profile.myId"),
           let uuid = UUID(uuidString: saved) {
            self.myId = uuid
        } else {
            let newId = UUID()
            UserDefaults.standard.set(newId.uuidString, forKey: "kiku.profile.myId")
            self.myId = newId
        }

        let appGroup = Self.appGroup
        appGroup?.set(self.name,              forKey: "kiku.profile.name")
        appGroup?.set(self.emoji,             forKey: "kiku.profile.emoji")
        appGroup?.set(self.iconMode.rawValue, forKey: "kiku.profile.iconMode")
        appGroup?.set(self.photoData,         forKey: "kiku.profile.photo")
    }

    // MARK: - Firestore 同期

    func syncFromFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            guard let self, let data = snapshot?.data(), error == nil else { return }
            DispatchQueue.main.async {
                if let name = data["name"] as? String, !name.isEmpty {
                    UserDefaults.standard.set(name, forKey: "kiku.profile.name")
                    Self.appGroup?.set(name, forKey: "kiku.profile.name")
                    self.name = name
                }
                if let emoji = data["emoji"] as? String {
                    UserDefaults.standard.set(emoji, forKey: "kiku.profile.emoji")
                    Self.appGroup?.set(emoji, forKey: "kiku.profile.emoji")
                    self.emoji = emoji
                }
                if let username = data["username"] as? String {
                    UserDefaults.standard.set(username, forKey: "kiku.profile.username")
                    self.username = username
                }
                if let stopTime = data["stopTimeActive"] as? Bool {
                    UserDefaults.standard.set(stopTime, forKey: "kiku.profile.stopTimeActive")
                    self.isStopTimeActive = stopTime
                }
                if let start = data["activeHourStart"] as? Int {
                    UserDefaults.standard.set(start, forKey: "kiku.profile.activeHourStart")
                    self.activeHourStart = start
                }
                if let end = data["activeHourEnd"] as? Int {
                    UserDefaults.standard.set(end, forKey: "kiku.profile.activeHourEnd")
                    self.activeHourEnd = end
                }
            }
        }
    }

    /// ユーザー名を Firestore に登録する（一意性をトランザクションで保証）
    /// - Returns: エラーメッセージ（成功時は nil）
    func setUsername(_ newUsername: String) async -> String? {
        guard let uid = Auth.auth().currentUser?.uid else { return "未認証です" }
        let trimmed = newUsername.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return "ユーザー名を入力してください" }

        let usernameRef = db.collection("usernames").document(trimmed)
        let userRef     = db.collection("users").document(uid)
        let oldUsername = username.isEmpty ? nil : username

        do {
            try await db.runTransaction { transaction, errorPointer in
                let usernameDoc: DocumentSnapshot
                do {
                    usernameDoc = try transaction.getDocument(usernameRef)
                } catch let e as NSError {
                    errorPointer?.pointee = e
                    return nil
                }
                // すでに他のユーザーが使用中
                if usernameDoc.exists,
                   let existingUid = usernameDoc.data()?["uid"] as? String,
                   existingUid != uid {
                    errorPointer?.pointee = NSError(
                        domain: "UsernameError",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "このユーザー名はすでに使われています"]
                    )
                    return nil
                }
                // 古いユーザー名を解放
                if let old = oldUsername, old != trimmed {
                    transaction.deleteDocument(self.db.collection("usernames").document(old))
                }
                transaction.setData(["uid": uid], forDocument: usernameRef)
                transaction.setData(["username": trimmed], forDocument: userRef, merge: true)
                return nil
            }
            await MainActor.run {
                UserDefaults.standard.set(trimmed, forKey: "kiku.profile.username")
                self.username = trimmed
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func saveProfileToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid,
              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        db.collection("users").document(uid).setData([
            "name":            name,
            "emoji":           emoji,
            "localId":         myId.uuidString,
            "stopTimeActive":  isStopTimeActive,
            "activeHourStart": activeHourStart,
            "activeHourEnd":   activeHourEnd,
            "updatedAt":       FieldValue.serverTimestamp()
        ], merge: true)
    }

    func completeSetup(name: String, emoji: String) {
        self.emoji = emoji
        self.name  = name.trimmingCharacters(in: .whitespaces)
    }

    func reset() {
        name      = ""
        emoji     = "👤"
        photoData = nil
        username  = ""
    }

    // MARK: - ストップモード 無料上限（1回/日）

    func hasUsedFreeStopTimeToday() -> Bool {
        guard let lastDate = UserDefaults.standard.object(forKey: "kiku.stopTime.lastDate") as? Date else { return false }
        let count = UserDefaults.standard.integer(forKey: "kiku.stopTime.count")
        return Calendar.current.isDateInToday(lastDate) && count >= 1
    }

    func recordStopTimeActivation() {
        let lastDate = UserDefaults.standard.object(forKey: "kiku.stopTime.lastDate") as? Date
        let count = UserDefaults.standard.integer(forKey: "kiku.stopTime.count")
        if let last = lastDate, Calendar.current.isDateInToday(last) {
            UserDefaults.standard.set(count + 1, forKey: "kiku.stopTime.count")
        } else {
            UserDefaults.standard.set(1, forKey: "kiku.stopTime.count")
            UserDefaults.standard.set(Date(), forKey: "kiku.stopTime.lastDate")
        }
    }
}

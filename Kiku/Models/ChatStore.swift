import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Answer Value Helpers

/// answerValue が "はい" 系かどうか（"yes" / "yes:text" / 時刻値 / 星評価 / 絵文字）
func answerIsYes(_ value: String) -> Bool {
    value == "yes" || value.hasPrefix("yes:") || isTimeValue(value)
        || value.hasPrefix("star:") || value.hasPrefix("emoji:")
}

/// answerValue が "いいえ" 系かどうか（"no" / "no:text"）
func answerIsNo(_ value: String) -> Bool {
    value == "no" || value.hasPrefix("no:")
}

/// チャット表示用テキスト（例: "✅ はい（明日なら行ける）"）
func answerDisplayText(_ value: String) -> String {
    if value == "yes"          { return "✅ はい" }
    if value.hasPrefix("yes:") { return "✅ はい（\(value.dropFirst(4))）" }
    if isTimeValue(value)         { return "🕐 \(value)" }
    if value == "no"              { return "❌ いいえ" }
    if value.hasPrefix("no:")     { return "❌ いいえ（\(value.dropFirst(3))）" }
    if value.hasPrefix("star:") {
        let n = Int(value.dropFirst(5)) ?? 0
        return "⭐️ \(String(repeating: "★", count: n))\(String(repeating: "☆", count: 5 - n))"
    }
    if value.hasPrefix("emoji:")  { return String(value.dropFirst(6)) }
    return "💬 \(value)"
}

// MARK: - ChatChannel

enum ChatChannel: String, Codable {
    case all = "all"
    case yes = "yes"
    case no  = "no"
}

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Codable {
    var id: UUID = UUID()
    var senderId: UUID?
    var senderName: String   = ""
    var senderEmoji: String  = ""
    var answerValue: String  = ""
    var channel: ChatChannel = .all
    var text: String
    var isFromMe: Bool
    var sentAt: Date = Date()
}

// MARK: - ChatMessage Codable（後方互換デコーダ）

extension ChatMessage {
    enum CodingKeys: String, CodingKey {
        case id, senderId, senderName, senderEmoji, answerValue, channel, text, isFromMe, sentAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,    forKey: .id)
        senderId    = try c.decodeIfPresent(UUID.self, forKey: .senderId)
        senderName  = try c.decodeIfPresent(String.self, forKey: .senderName)  ?? ""
        senderEmoji = try c.decodeIfPresent(String.self, forKey: .senderEmoji) ?? ""
        answerValue = try c.decodeIfPresent(String.self, forKey: .answerValue) ?? ""
        channel     = try c.decodeIfPresent(ChatChannel.self, forKey: .channel) ?? .all
        text        = try c.decode(String.self,  forKey: .text)
        isFromMe    = try c.decode(Bool.self,    forKey: .isFromMe)
        sentAt      = try c.decodeIfPresent(Date.self, forKey: .sentAt) ?? Date()
    }
}

// MARK: - ChatSession

struct ChatSession: Identifiable, Codable {
    var id: UUID = UUID()
    var questionId: UUID
    var questionText: String
    var memberAnswers: [String: String] = [:]
    var messages: [ChatMessage] = []
    var createdAt: Date = Date()
    var lastReadMessageCount: Int = 0

    var lastMessageAt: Date {
        messages.last?.sentAt ?? createdAt
    }

    var yesMembers: Set<String> { Set(memberAnswers.filter { answerIsYes($0.value) }.keys) }
    var noMembers:  Set<String> { Set(memberAnswers.filter { answerIsNo($0.value)  }.keys) }
}

extension ChatSession {
    enum CodingKeys: String, CodingKey {
        case id, questionId, questionText, memberAnswers, messages, createdAt, lastReadMessageCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decode(UUID.self,             forKey: .id)
        questionId           = try c.decode(UUID.self,             forKey: .questionId)
        questionText         = try c.decode(String.self,           forKey: .questionText)
        memberAnswers        = try c.decodeIfPresent([String: String].self, forKey: .memberAnswers) ?? [:]
        messages             = try c.decodeIfPresent([ChatMessage].self,   forKey: .messages)       ?? []
        createdAt            = try c.decodeIfPresent(Date.self,            forKey: .createdAt)      ?? Date()
        lastReadMessageCount = try c.decodeIfPresent(Int.self,             forKey: .lastReadMessageCount) ?? 0
    }
}

// MARK: - ChatStore

class ChatStore: ObservableObject {
    @Published var sessions: [ChatSession] = [] {
        didSet {
            if !isUpdatingFromFirestore { save() }
        }
    }

    private let key = "kiku.chats.v2"
    private let db  = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var isUpdatingFromFirestore = false

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) {
            sessions = decoded
        }
    }

    // MARK: - Firestore リスナー

    func startListening(forUID uid: String) {
        stopListening()
        listener = db.collection("chats")
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

    private func mergeFromFirestore(_ docs: [QueryDocumentSnapshot]) {
        var merged = self.sessions
        for doc in docs {
            guard let session = sessionFromFirestore(doc) else { continue }
            if let idx = merged.firstIndex(where: { $0.questionId == session.questionId }) {
                // 既存セッション: メッセージをマージ（重複なし）
                let existingIds = Set(merged[idx].messages.map { $0.id })
                let newMessages = session.messages.filter { !existingIds.contains($0.id) }
                merged[idx].messages.append(contentsOf: newMessages)
                merged[idx].memberAnswers = session.memberAnswers
            } else {
                merged.append(session)
            }
        }
        DispatchQueue.main.async {
            self.isUpdatingFromFirestore = true
            self.sessions = merged
            self.isUpdatingFromFirestore = false
        }
    }

    // MARK: - 回答時にセッションを作成/更新

    func unlock(
        questionId:   UUID,
        memberId:     UUID,
        questionText: String,
        answerValue:  String,
        friendName:   String,
        friendEmoji:  String
    ) {
        let memberKey = memberId.uuidString

        if let idx = sessions.firstIndex(where: { $0.questionId == questionId }) {
            guard sessions[idx].memberAnswers[memberKey] == nil else { return }
            sessions[idx].memberAnswers[memberKey] = answerValue

            let joinChannel: ChatChannel = answerIsYes(answerValue) ? .yes : .no
            let message = ChatMessage(
                senderId:    memberId,
                senderName:  friendName,
                senderEmoji: friendEmoji,
                answerValue: answerValue,
                channel:     joinChannel,
                text:        "\(answerDisplayText(answerValue)) と回答しました",
                isFromMe:    false
            )
            sessions[idx].messages.append(message)
            saveSessionToFirestore(sessions[idx])
        } else {
            var session = ChatSession(questionId: questionId, questionText: questionText)
            session.memberAnswers[memberKey] = answerValue

            let joinChannel: ChatChannel = answerIsYes(answerValue) ? .yes : .no
            session.messages.append(ChatMessage(
                senderId:    memberId,
                senderName:  friendName,
                senderEmoji: friendEmoji,
                answerValue: answerValue,
                channel:     joinChannel,
                text:        "\(answerDisplayText(answerValue)) と回答しました",
                isFromMe:    false
            ))
            sessions.append(session)
            saveSessionToFirestore(session)
        }
    }

    // MARK: - メッセージ送信

    func send(
        text:        String,
        isFromMe:    Bool,
        senderName:  String,
        senderEmoji: String,
        answerValue: String      = "",
        channel:     ChatChannel = .all,
        senderId:    UUID?       = nil,
        to sessionId: UUID
    ) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let message = ChatMessage(
            senderId:    senderId,
            senderName:  senderName,
            senderEmoji: senderEmoji,
            answerValue: answerValue,
            channel:     channel,
            text:        text,
            isFromMe:    isFromMe
        )
        sessions[idx].messages.append(message)
        saveSessionToFirestore(sessions[idx])
    }

    // MARK: - ヘルパー

    func deleteSession(id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        sessions.removeAll { $0.id == id }
        db.collection("chats").document(session.questionId.uuidString).delete()
    }

    func session(for questionId: UUID) -> ChatSession? {
        sessions.first { $0.questionId == questionId }
    }

    func markAsRead(sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].lastReadMessageCount = sessions[idx].messages.count
    }

    func unreadCount(for sessionId: UUID) -> Int {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return 0 }
        return max(0, session.messages.count - session.lastReadMessageCount)
    }

    var totalUnread: Int {
        sessions.reduce(0) { $0 + max(0, $1.messages.count - $1.lastReadMessageCount) }
    }

    // MARK: - Firestore データ変換

    private func saveSessionToFirestore(_ session: ChatSession) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let messagesData: [[String: Any]] = session.messages.map { m in
            var dict: [String: Any] = [
                "id":          m.id.uuidString,
                "senderName":  m.senderName,
                "senderEmoji": m.senderEmoji,
                "answerValue": m.answerValue,
                "channel":     m.channel.rawValue,
                "text":        m.text,
                "isFromMe":    m.isFromMe,
                "sentAt":      Timestamp(date: m.sentAt)
            ]
            if let sid = m.senderId { dict["senderId"] = sid.uuidString }
            return dict
        }
        let data: [String: Any] = [
            "questionId":    session.questionId.uuidString,
            "questionText":  session.questionText,
            "memberAnswers": session.memberAnswers,
            "createdAt":     Timestamp(date: session.createdAt),
            "createdBy":     uid,
            "messages":      messagesData
        ]
        db.collection("chats").document(session.questionId.uuidString).setData(data)
    }

    private func sessionFromFirestore(_ doc: QueryDocumentSnapshot) -> ChatSession? {
        let data = doc.data()
        guard let questionIdStr = data["questionId"] as? String,
              let questionId    = UUID(uuidString: questionIdStr),
              let questionText  = data["questionText"] as? String else { return nil }

        let memberAnswers = data["memberAnswers"] as? [String: String] ?? [:]
        let createdAt     = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let messagesData  = data["messages"] as? [[String: Any]] ?? []

        let messages: [ChatMessage] = messagesData.compactMap { m in
            guard let idStr  = m["id"] as? String,
                  let id     = UUID(uuidString: idStr),
                  let text   = m["text"] as? String,
                  let isFromMe = m["isFromMe"] as? Bool else { return nil }
            let senderId    = (m["senderId"] as? String).flatMap { UUID(uuidString: $0) }
            let channel     = ChatChannel(rawValue: m["channel"] as? String ?? "all") ?? .all
            let sentAt      = (m["sentAt"] as? Timestamp)?.dateValue() ?? Date()
            return ChatMessage(
                id:          id,
                senderId:    senderId,
                senderName:  m["senderName"]  as? String ?? "",
                senderEmoji: m["senderEmoji"] as? String ?? "",
                answerValue: m["answerValue"] as? String ?? "",
                channel:     channel,
                text:        text,
                isFromMe:    isFromMe,
                sentAt:      sentAt
            )
        }

        var session = ChatSession(questionId: questionId, questionText: questionText)
        session.memberAnswers = memberAnswers
        session.messages      = messages
        session.createdAt     = createdAt
        return session
    }

    // MARK: - ローカル永続化

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

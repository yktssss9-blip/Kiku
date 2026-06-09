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
    /// 絵文字文字列 → リアクションした人の senderId(UUID文字列) の配列
    var reactions: [String: [String]] = [:]
    /// メッセージ送信者の Firebase UID（通知の送信先除外に使用。システムメッセージは nil）
    var senderFirebaseUID: String? = nil
}

// MARK: - ChatMessage Codable（後方互換デコーダ）

extension ChatMessage {
    enum CodingKeys: String, CodingKey {
        case id, senderId, senderName, senderEmoji, answerValue, channel, text, isFromMe, sentAt, reactions, senderFirebaseUID
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
        reactions         = try c.decodeIfPresent([String: [String]].self, forKey: .reactions) ?? [:]
        senderFirebaseUID = try c.decodeIfPresent(String.self, forKey: .senderFirebaseUID)
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
    /// 質問作成者のFirebase UID（自分のチャットか受信したチャットかの判定に使用。Firestoreの "createdBy" と対応）
    var creatorUID: String? = nil

    var lastMessageAt: Date {
        messages.last?.sentAt ?? createdAt
    }

    var yesMembers: Set<String> { Set(memberAnswers.filter { answerIsYes($0.value) }.keys) }
    var noMembers:  Set<String> { Set(memberAnswers.filter { answerIsNo($0.value)  }.keys) }
}

extension ChatSession {
    enum CodingKeys: String, CodingKey {
        case id, questionId, questionText, memberAnswers, messages, createdAt, lastReadMessageCount, creatorUID
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
        creatorUID           = try c.decodeIfPresent(String.self,          forKey: .creatorUID)
    }
}

// MARK: - ChatStore

class ChatStore: ObservableObject {
    @Published var sessions: [ChatSession] = [] {
        didSet {
            if !isUpdatingFromFirestore { save() }
        }
    }
    /// 他ユーザーが作成した質問から開放されたチャット（Firestoreが正・ローカル永続化なし）
    @Published var receivedSessions: [ChatSession] = []

    private let key = "kiku.chats.v2"
    private let db  = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var receivedListener: ListenerRegistration?
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

    /// 他ユーザーが作成した質問のうち、自分が回答してチャットに参加しているものをリッスン
    func startListeningReceived(forUID uid: String) {
        stopListeningReceived()
        receivedListener = db.collection("chats")
            .whereField("participantUIDs", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                self.mergeReceivedFromFirestore(docs, forUID: uid)
            }
    }

    func stopListeningReceived() {
        receivedListener?.remove()
        receivedListener = nil
    }

    private func mergeFromFirestore(_ docs: [QueryDocumentSnapshot]) {
        var merged = self.sessions
        for doc in docs {
            guard let session = session(fromFirestoreData: doc.data()) else { continue }
            if let idx = merged.firstIndex(where: { $0.questionId == session.questionId }) {
                // 既存セッション: メッセージをマージ（重複なし）
                let existingIds = Set(merged[idx].messages.map { $0.id })
                let newMessages = session.messages.filter { !existingIds.contains($0.id) }
                merged[idx].messages.append(contentsOf: newMessages)
                merged[idx].memberAnswers = session.memberAnswers
                merged[idx].creatorUID    = session.creatorUID
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

    private func mergeReceivedFromFirestore(_ docs: [QueryDocumentSnapshot], forUID uid: String) {
        var merged = self.receivedSessions
        for doc in docs {
            let data = doc.data()
            // 自分が作成したチャットは sessions 側で扱うのでスキップ
            guard data["createdBy"] as? String != uid,
                  let session = session(fromFirestoreData: data) else { continue }
            if let idx = merged.firstIndex(where: { $0.questionId == session.questionId }) {
                let existingIds = Set(merged[idx].messages.map { $0.id })
                let newMessages = session.messages.filter { !existingIds.contains($0.id) }
                merged[idx].messages.append(contentsOf: newMessages)
                merged[idx].memberAnswers = session.memberAnswers
                merged[idx].creatorUID    = session.creatorUID
            } else {
                merged.append(session)
            }
        }
        DispatchQueue.main.async {
            self.receivedSessions = merged
        }
    }

    // MARK: - 回答時にセッションを作成/更新

    /// - Parameters:
    ///   - ownerUID: 質問作成者のUID（チャットの "createdBy"。自分の質問なら自分のUID、受信した質問なら相手のUID）
    ///   - participantUID: 今回回答した相手のUID（自分の質問に友達が回答した場合は friend.firebaseUID、受信した質問に自分が回答した場合は自分のUID）。不明な場合は nil
    func unlock(
        questionId:     UUID,
        memberId:       UUID,
        questionText:   String,
        answerValue:    String,
        friendName:     String,
        friendEmoji:    String,
        ownerUID:       String,
        participantUID: String? = nil
    ) {
        let memberKey = memberId.uuidString
        let myUID = Auth.auth().currentUser?.uid
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

        // ローカル楽観的更新
        if let idx = sessions.firstIndex(where: { $0.questionId == questionId }) {
            guard sessions[idx].memberAnswers[memberKey] == nil else { return }
            sessions[idx].memberAnswers[memberKey] = answerValue
            sessions[idx].messages.append(message)
        } else if let idx = receivedSessions.firstIndex(where: { $0.questionId == questionId }) {
            guard receivedSessions[idx].memberAnswers[memberKey] == nil else { return }
            receivedSessions[idx].memberAnswers[memberKey] = answerValue
            receivedSessions[idx].messages.append(message)
        } else {
            var session = ChatSession(questionId: questionId, questionText: questionText)
            session.memberAnswers[memberKey] = answerValue
            session.messages.append(message)
            session.creatorUID = ownerUID
            if ownerUID == myUID {
                sessions.append(session)
            } else {
                receivedSessions.append(session)
            }
        }

        var participantUIDs = [ownerUID]
        if let participantUID, !participantUID.isEmpty, participantUID != ownerUID {
            participantUIDs.append(participantUID)
        }

        mutateSessionInFirestore(
            questionId:      questionId,
            questionText:    questionText,
            ownerUID:        ownerUID,
            participantUIDs: participantUIDs
        ) { session in
            guard session.memberAnswers[memberKey] == nil else { return }
            session.memberAnswers[memberKey] = answerValue
            session.messages.append(message)
        }
    }

    // MARK: - 回答変更時のメッセージ上書き

    /// `unlock` で挿入された回答メッセージを変更後の内容に書き換える（「（変更済み）」を付記）
    func updateAnswerMessage(questionId: UUID, memberId: UUID, newAnswerValue: String) {
        let memberKey = memberId.uuidString
        let newChannel: ChatChannel = answerIsYes(newAnswerValue) ? .yes : .no
        let newText = "\(answerDisplayText(newAnswerValue)) と回答しました（変更済み）"

        func apply(to session: inout ChatSession) -> Bool {
            guard let midx = session.messages.firstIndex(where: {
                $0.senderId == memberId && !$0.answerValue.isEmpty
            }) else { return false }
            session.messages[midx].answerValue = newAnswerValue
            session.messages[midx].channel     = newChannel
            session.messages[midx].text        = newText
            session.memberAnswers[memberKey]   = newAnswerValue
            return true
        }

        var resolvedQuestionId: UUID? = nil
        var resolvedQuestionText: String? = nil

        if let idx = sessions.firstIndex(where: { $0.questionId == questionId }), apply(to: &sessions[idx]) {
            resolvedQuestionId   = sessions[idx].questionId
            resolvedQuestionText = sessions[idx].questionText
        } else if let idx = receivedSessions.firstIndex(where: { $0.questionId == questionId }), apply(to: &receivedSessions[idx]) {
            resolvedQuestionId   = receivedSessions[idx].questionId
            resolvedQuestionText = receivedSessions[idx].questionText
        }

        guard let qId = resolvedQuestionId, let qText = resolvedQuestionText else { return }

        mutateSessionInFirestore(questionId: qId, questionText: qText) { session in
            _ = apply(to: &session)
        }
    }

    // MARK: - メッセージ送信

    func send(
        text:              String,
        isFromMe:          Bool,
        senderName:        String,
        senderEmoji:       String,
        answerValue:       String      = "",
        channel:           ChatChannel = .all,
        senderId:          UUID?       = nil,
        senderFirebaseUID: String?     = nil,
        to sessionId:      UUID
    ) {
        let message = ChatMessage(
            senderId:          senderId,
            senderName:        senderName,
            senderEmoji:       senderEmoji,
            answerValue:       answerValue,
            channel:           channel,
            text:              text,
            isFromMe:          isFromMe,
            senderFirebaseUID: senderFirebaseUID
        )

        let questionId: UUID
        let questionText: String
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].messages.append(message)
            questionId   = sessions[idx].questionId
            questionText = sessions[idx].questionText
        } else if let idx = receivedSessions.firstIndex(where: { $0.id == sessionId }) {
            receivedSessions[idx].messages.append(message)
            questionId   = receivedSessions[idx].questionId
            questionText = receivedSessions[idx].questionText
        } else {
            return
        }

        mutateSessionInFirestore(questionId: questionId, questionText: questionText) { session in
            guard !session.messages.contains(where: { $0.id == message.id }) else { return }
            session.messages.append(message)
        }
    }

    // MARK: - リアクション

    func toggleReaction(emoji: String, messageId: UUID, sessionId: UUID, senderId: UUID) {
        let senderKey = senderId.uuidString

        func toggle(in messages: inout [ChatMessage]) -> Bool {
            guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return false }
            var senders = messages[idx].reactions[emoji] ?? []
            if let i = senders.firstIndex(of: senderKey) {
                senders.remove(at: i)
            } else {
                senders.append(senderKey)
            }
            if senders.isEmpty {
                messages[idx].reactions.removeValue(forKey: emoji)
            } else {
                messages[idx].reactions[emoji] = senders
            }
            return true
        }

        var resolvedQuestionId: UUID? = nil
        var resolvedQuestionText: String? = nil

        if let idx = sessions.firstIndex(where: { $0.id == sessionId }), toggle(in: &sessions[idx].messages) {
            resolvedQuestionId   = sessions[idx].questionId
            resolvedQuestionText = sessions[idx].questionText
        } else if let idx = receivedSessions.firstIndex(where: { $0.id == sessionId }), toggle(in: &receivedSessions[idx].messages) {
            resolvedQuestionId   = receivedSessions[idx].questionId
            resolvedQuestionText = receivedSessions[idx].questionText
        }

        guard let questionId = resolvedQuestionId, let questionText = resolvedQuestionText else { return }

        mutateSessionInFirestore(questionId: questionId, questionText: questionText) { session in
            _ = toggle(in: &session.messages)
        }
    }

    // MARK: - ヘルパー

    /// 自分が作成した質問のチャットかどうか（受信したチャットでは削除操作を出さない判定に使用）
    func isOwn(_ session: ChatSession) -> Bool {
        sessions.contains { $0.id == session.id }
    }

    func deleteSession(id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        sessions.removeAll { $0.id == id }
        db.collection("chats").document(session.questionId.uuidString).delete()
    }

    func session(for questionId: UUID) -> ChatSession? {
        sessions.first { $0.questionId == questionId } ?? receivedSessions.first { $0.questionId == questionId }
    }

    func markAsRead(sessionId: UUID) {
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].lastReadMessageCount = sessions[idx].messages.count
        } else if let idx = receivedSessions.firstIndex(where: { $0.id == sessionId }) {
            receivedSessions[idx].lastReadMessageCount = receivedSessions[idx].messages.count
        }
    }

    func unreadCount(for sessionId: UUID) -> Int {
        if let session = sessions.first(where: { $0.id == sessionId }) {
            return max(0, session.messages.count - session.lastReadMessageCount)
        }
        if let session = receivedSessions.first(where: { $0.id == sessionId }) {
            return max(0, session.messages.count - session.lastReadMessageCount)
        }
        return 0
    }

    var totalUnread: Int {
        let own      = sessions.reduce(0)         { $0 + max(0, $1.messages.count - $1.lastReadMessageCount) }
        let received = receivedSessions.reduce(0) { $0 + max(0, $1.messages.count - $1.lastReadMessageCount) }
        return own + received
    }

    // MARK: - Firestore 書き込み（トランザクションでリモート状態とマージしてから保存）

    /// リモートの最新状態を読み取り、`mutate` でローカルの変更を適用してから書き戻す。
    /// 複数の参加者が同時に書き込んでも、互いの変更（メッセージ・回答・リアクション）を失わない。
    /// セッションが新規作成される場合のみ `ownerUID` / `participantUIDs` が使用される（既存ドキュメントの値を優先）。
    private func mutateSessionInFirestore(
        questionId:      UUID,
        questionText:    String,
        ownerUID:        String?   = nil,
        participantUIDs: [String]? = nil,
        mutate: @escaping (inout ChatSession) -> Void
    ) {
        let docRef = db.collection("chats").document(questionId.uuidString)
        let myUID = Auth.auth().currentUser?.uid

        db.runTransaction({ [weak self] txn, errorPointer -> Any? in
            guard let self else { return nil }
            let snapshot: DocumentSnapshot
            do {
                snapshot = try txn.getDocument(docRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            var session: ChatSession
            let resolvedOwnerUID: String
            let resolvedParticipantUIDs: [String]

            if snapshot.exists, let data = snapshot.data(), let existing = self.session(fromFirestoreData: data) {
                session = existing
                resolvedOwnerUID        = data["createdBy"] as? String ?? (ownerUID ?? myUID ?? "")
                resolvedParticipantUIDs = data["participantUIDs"] as? [String] ?? (participantUIDs ?? [])
            } else {
                session = ChatSession(questionId: questionId, questionText: questionText)
                resolvedOwnerUID        = ownerUID ?? myUID ?? ""
                resolvedParticipantUIDs = participantUIDs ?? []
            }

            mutate(&session)

            let data = self.firestoreData(for: session, ownerUID: resolvedOwnerUID, participantUIDs: resolvedParticipantUIDs)
            txn.setData(data, forDocument: docRef)
            return nil
        }) { _, error in
            if let error {
                print("[ChatStore] Firestore更新失敗: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Firestore データ変換

    private func firestoreData(for session: ChatSession, ownerUID: String, participantUIDs: [String]) -> [String: Any] {
        let messagesData: [[String: Any]] = session.messages.map { m in
            var dict: [String: Any] = [
                "id":          m.id.uuidString,
                "senderName":  m.senderName,
                "senderEmoji": m.senderEmoji,
                "answerValue": m.answerValue,
                "channel":     m.channel.rawValue,
                "text":        m.text,
                "isFromMe":    m.isFromMe,
                "sentAt":      Timestamp(date: m.sentAt),
                "reactions":   m.reactions
            ]
            if let sid = m.senderId           { dict["senderId"]          = sid.uuidString }
            if let uid = m.senderFirebaseUID  { dict["senderFirebaseUID"] = uid }
            return dict
        }
        return [
            "questionId":      session.questionId.uuidString,
            "questionText":    session.questionText,
            "memberAnswers":   session.memberAnswers,
            "createdAt":       Timestamp(date: session.createdAt),
            "createdBy":       ownerUID,
            "participantUIDs": participantUIDs,
            "messages":        messagesData
        ]
    }

    private func session(fromFirestoreData data: [String: Any]) -> ChatSession? {
        guard let questionIdStr = data["questionId"] as? String,
              let questionId    = UUID(uuidString: questionIdStr),
              let questionText  = data["questionText"] as? String else { return nil }

        let memberAnswers = data["memberAnswers"] as? [String: String] ?? [:]
        let createdAt     = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let creatorUID    = data["createdBy"] as? String
        let messagesData  = data["messages"] as? [[String: Any]] ?? []

        let messages: [ChatMessage] = messagesData.compactMap { m in
            guard let idStr  = m["id"] as? String,
                  let id     = UUID(uuidString: idStr),
                  let text   = m["text"] as? String,
                  let isFromMe = m["isFromMe"] as? Bool else { return nil }
            let senderId          = (m["senderId"] as? String).flatMap { UUID(uuidString: $0) }
            let channel           = ChatChannel(rawValue: m["channel"] as? String ?? "all") ?? .all
            let sentAt            = (m["sentAt"] as? Timestamp)?.dateValue() ?? Date()
            let reactions         = m["reactions"] as? [String: [String]] ?? [:]
            let senderFirebaseUID = m["senderFirebaseUID"] as? String
            return ChatMessage(
                id:                id,
                senderId:          senderId,
                senderName:        m["senderName"]  as? String ?? "",
                senderEmoji:       m["senderEmoji"] as? String ?? "",
                answerValue:       m["answerValue"] as? String ?? "",
                channel:           channel,
                text:              text,
                isFromMe:          isFromMe,
                sentAt:            sentAt,
                reactions:         reactions,
                senderFirebaseUID: senderFirebaseUID
            )
        }

        var session = ChatSession(questionId: questionId, questionText: questionText)
        session.memberAnswers = memberAnswers
        session.messages      = messages
        session.createdAt     = createdAt
        session.creatorUID    = creatorUID
        return session
    }

    // MARK: - ローカル永続化

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - ChatSession: Hashable（NavigationLink(value:) 用）

extension ChatSession: Hashable, Equatable {
    static func == (lhs: ChatSession, rhs: ChatSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

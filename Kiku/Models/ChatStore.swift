import SwiftUI

// MARK: - Answer Value Helpers

/// answerValue が "はい" 系かどうか（"yes" / "yes:text" / 時刻値）
func answerIsYes(_ value: String) -> Bool {
    value == "yes" || value.hasPrefix("yes:") || isTimeValue(value)
}

/// answerValue が "いいえ" 系かどうか（"no" / "no:text"）
func answerIsNo(_ value: String) -> Bool {
    value == "no" || value.hasPrefix("no:")
}

/// チャット表示用テキスト（例: "✅ はい（明日なら行ける）"）
func answerDisplayText(_ value: String) -> String {
    if value == "yes"          { return "✅ はい" }
    if value.hasPrefix("yes:") { return "✅ はい（\(value.dropFirst(4))）" }
    if isTimeValue(value)      { return "🕐 \(value)" }
    if value == "no"           { return "❌ いいえ" }
    if value.hasPrefix("no:")  { return "❌ いいえ（\(value.dropFirst(3))）" }
    return "💬 \(value)"
}

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Codable {
    var id: UUID = UUID()
    var senderId: UUID?      // nil = 自分（主催者）
    var senderName: String   = ""
    var senderEmoji: String  = ""
    var answerValue: String  = ""   // 送信者の回答（"yes"/"no"/""）— フィルタ用
    var text: String
    var isFromMe: Bool
    var sentAt: Date = Date()
}

// MARK: - ChatSession（質問単位のグループチャット）

struct ChatSession: Identifiable, Codable {
    var id: UUID = UUID()
    var questionId: UUID
    var questionText: String
    var memberAnswers: [String: String] = [:]  // memberId.uuidString → "yes"/"no"
    var messages: [ChatMessage] = []
    var createdAt: Date = Date()
    var lastReadMessageCount: Int = 0  // 既読管理: ChatView を開いた時点のメッセージ数

    // 最新メッセージの時刻（一覧ソート用）
    var lastMessageAt: Date {
        messages.last?.sentAt ?? createdAt
    }

    // はい回答者のmemberIdSet
    var yesMembers: Set<String> { Set(memberAnswers.filter { answerIsYes($0.value) }.keys) }
    var noMembers:  Set<String> { Set(memberAnswers.filter { answerIsNo($0.value)  }.keys) }
}

// MARK: - ChatSession Codable（後方互換デコーダ）

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
        didSet { save() }
    }

    private let key = "kiku.chats.v2"   // v2 = グループチャット形式（旧データとキー分離）

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) {
            sessions = decoded
        }
    }

    // MARK: 回答時に呼ばれる — グループセッションにメンバーを追加

    func unlock(
        questionId:   UUID,
        memberId:     UUID,
        questionText: String,
        answerValue:  String,
        friendName:   String,
        friendEmoji:  String
    ) {
        let memberKey = memberId.uuidString

        // 同じ質問のセッションが既に存在するか確認
        if let idx = sessions.firstIndex(where: { $0.questionId == questionId }) {
            // 既に同じメンバーが登録済みなら何もしない
            guard sessions[idx].memberAnswers[memberKey] == nil else { return }

            sessions[idx].memberAnswers[memberKey] = answerValue

            // 回答メッセージを追加
            sessions[idx].messages.append(ChatMessage(
                senderId:    memberId,
                senderName:  friendName,
                senderEmoji: friendEmoji,
                answerValue: answerValue,
                text:        "\(answerDisplayText(answerValue)) と回答しました",
                isFromMe:    false
            ))
        } else {
            // 新規グループセッションを作成
            var session = ChatSession(questionId: questionId, questionText: questionText)
            session.memberAnswers[memberKey] = answerValue

            session.messages.append(ChatMessage(
                senderId:    memberId,
                senderName:  friendName,
                senderEmoji: friendEmoji,
                answerValue: answerValue,
                text:        "\(answerDisplayText(answerValue)) と回答しました",
                isFromMe:    false
            ))
            sessions.append(session)
        }
    }

    // MARK: メッセージ送信

    func send(
        text:        String,
        isFromMe:    Bool,
        senderName:  String,
        senderEmoji: String,
        answerValue: String = "",
        senderId:    UUID?  = nil,
        to sessionId: UUID
    ) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].messages.append(ChatMessage(
            senderId:    senderId,
            senderName:  senderName,
            senderEmoji: senderEmoji,
            answerValue: answerValue,
            text:        text,
            isFromMe:    isFromMe
        ))
    }

    // MARK: ヘルパー

    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
    }

    /// 特定の質問のセッションを取得
    func session(for questionId: UUID) -> ChatSession? {
        sessions.first { $0.questionId == questionId }
    }

    /// 既読を更新（ChatView を開いた時点で呼ぶ）
    func markAsRead(sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].lastReadMessageCount = sessions[idx].messages.count
    }

    /// セッション単位の未読数（messages.count - lastReadMessageCount）
    func unreadCount(for sessionId: UUID) -> Int {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return 0 }
        return max(0, session.messages.count - session.lastReadMessageCount)
    }

    /// 全セッションの未読合計
    var totalUnread: Int {
        sessions.reduce(0) { $0 + max(0, $1.messages.count - $1.lastReadMessageCount) }
    }

    // MARK: 永続化

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

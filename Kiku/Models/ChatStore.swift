import SwiftUI

struct ChatMessage: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var isFromMe: Bool      // true = 自分（発信者）, false = メンバー
    var sentAt: Date = Date()
}

struct ChatSession: Identifiable, Codable {
    var id: UUID = UUID()
    var questionId: UUID
    var memberId: UUID
    var questionText: String   // どの質問で開放されたか（表示用）
    var answerValue: String    // "yes" or "no"（チャット開放のきっかけとなった回答）
    var unlockedAt: Date = Date()
    var messages: [ChatMessage] = []

    // 既存の保存データ（answerValue なし）との後方互換
    private enum CodingKeys: String, CodingKey {
        case id, questionId, memberId, questionText, answerValue, unlockedAt, messages
    }
    init(questionId: UUID, memberId: UUID, questionText: String, answerValue: String) {
        self.questionId   = questionId
        self.memberId     = memberId
        self.questionText = questionText
        self.answerValue  = answerValue
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,          forKey: .id)
        questionId   = try c.decode(UUID.self,          forKey: .questionId)
        memberId     = try c.decode(UUID.self,          forKey: .memberId)
        questionText = try c.decode(String.self,        forKey: .questionText)
        answerValue  = (try? c.decode(String.self,      forKey: .answerValue)) ?? ""
        unlockedAt   = try c.decode(Date.self,          forKey: .unlockedAt)
        messages     = try c.decode([ChatMessage].self, forKey: .messages)
    }
}

class ChatStore: ObservableObject {
    @Published var sessions: [ChatSession] = [] {
        didSet { save() }
    }

    private let key = "kiku.chats"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) {
            sessions = decoded
        }
    }

    // 回答時に呼ばれる：チャットを開放し、回答内容を最初のメッセージとして追加
    func unlock(questionId: UUID, memberId: UUID, questionText: String, answerValue: String) {
        let alreadyExists = sessions.contains {
            $0.questionId == questionId && $0.memberId == memberId
        }
        guard !alreadyExists else { return }

        var session = ChatSession(
            questionId:   questionId,
            memberId:     memberId,
            questionText: questionText,
            answerValue:  answerValue
        )

        // 回答内容を最初のメッセージとして自動挿入
        let answerLabel = answerValue == "yes" ? "✅ はい" : "❌ いいえ"
        session.messages.append(ChatMessage(
            text:     "「\(questionText)」に \(answerLabel) と回答しました",
            isFromMe: false
        ))

        sessions.append(session)
    }

    // メッセージ送信
    func send(text: String, isFromMe: Bool, to sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].messages.append(ChatMessage(text: text, isFromMe: isFromMe))
    }

    // 特定メンバーとの全チャットセッション
    func sessions(for memberId: UUID) -> [ChatSession] {
        sessions.filter { $0.memberId == memberId }
                .sorted { $0.unlockedAt > $1.unlockedAt }
    }

    // 未読メッセージ総数
    var totalUnread: Int {
        sessions.reduce(0) { $0 + $1.messages.filter { !$0.isFromMe }.count }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

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
    var unlockedAt: Date = Date()
    var messages: [ChatMessage] = []
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

    // 回答時に呼ばれる：チャットを開放
    func unlock(questionId: UUID, memberId: UUID, questionText: String) {
        let alreadyExists = sessions.contains {
            $0.questionId == questionId && $0.memberId == memberId
        }
        guard !alreadyExists else { return }
        sessions.append(ChatSession(
            questionId:   questionId,
            memberId:     memberId,
            questionText: questionText
        ))
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

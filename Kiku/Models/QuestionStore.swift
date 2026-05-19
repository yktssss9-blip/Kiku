import SwiftUI

struct Answer: Codable {
    var memberId: UUID
    var value: String       // "yes" / "no" / "pending"
    var answeredAt: Date?
}

struct Question: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var groupId: UUID?      // nil = 全体送信
    var isBroadcast: Bool = false
    var answers: [Answer]
    var createdAt: Date = Date()

    func summary() -> (yes: Int, no: Int, pending: Int) {
        let yes     = answers.filter { $0.value == "yes" }.count
        let no      = answers.filter { $0.value == "no"  }.count
        let pending = answers.filter { $0.value == "pending" }.count
        return (yes, no, pending)
    }
}

class QuestionStore: ObservableObject {
    @Published var questions: [Question] = [] {
        didSet { save() }
    }

    private let key = "kiku.questions"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Question].self, from: data) {
            questions = decoded
        }
    }

    // グループへの送信
    func send(text: String, to group: KikuGroup, friends: [Friend] = []) {
        let answers = group.memberIds.map { Answer(memberId: $0, value: "pending") }
        let question = Question(text: text, groupId: group.id, answers: answers)
        questions.append(question)

        // 各メンバーにローカル通知を送信
        for memberId in group.memberIds {
            let friend = friends.first { $0.id == memberId }
            NotificationManager.shared.scheduleQuestion(
                questionId:  question.id,
                memberId:    memberId,
                memberName:  friend?.name  ?? "メンバー",
                memberEmoji: friend?.emoji ?? "👤",
                questionText: text
            )
        }
    }

    // 全体送信（全友達へ）
    func sendBroadcast(text: String, to friends: [Friend]) {
        let answers = friends.map { Answer(memberId: $0.id, value: "pending") }
        questions.append(Question(text: text, groupId: nil, isBroadcast: true, answers: answers))
    }

    // chatStore を外から注入して回答時にチャットを開放する
    var onAnswered: ((UUID, UUID, String) -> Void)?

    func submit(questionId: UUID, memberId: UUID, value: String) {
        guard let idx = questions.firstIndex(where: { $0.id == questionId }),
              let aidx = questions[idx].answers.firstIndex(where: { $0.memberId == memberId })
        else { return }
        questions[idx].answers[aidx].value = value
        questions[idx].answers[aidx].answeredAt = Date()
        // チャット開放コールバック
        let questionText = questions[idx].text
        onAnswered?(questionId, memberId, questionText)
    }

    func questions(for group: KikuGroup) -> [Question] {
        questions.filter { $0.groupId == group.id }
                 .sorted { $0.createdAt > $1.createdAt }
    }

    var broadcastQuestions: [Question] {
        questions.filter { $0.isBroadcast }
                 .sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(questions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

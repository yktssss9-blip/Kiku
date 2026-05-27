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
    var choices: [String] = ["yes", "no"]  // AnswerChoice.rawValue で保存

    // 既存データとの後方互換デコード
    enum CodingKeys: String, CodingKey {
        case id, text, groupId, isBroadcast, answers, createdAt, choices
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,     forKey: .id)
        text        = try c.decode(String.self,   forKey: .text)
        groupId     = try c.decodeIfPresent(UUID.self,   forKey: .groupId)
        isBroadcast = try c.decodeIfPresent(Bool.self,   forKey: .isBroadcast) ?? false
        answers     = try c.decode([Answer].self, forKey: .answers)
        createdAt   = try c.decodeIfPresent(Date.self,   forKey: .createdAt) ?? Date()
        choices     = try c.decodeIfPresent([String].self, forKey: .choices) ?? ["yes", "no"]
    }
    init(id: UUID = UUID(), text: String, groupId: UUID? = nil,
         isBroadcast: Bool = false, answers: [Answer],
         createdAt: Date = Date(), choices: [String] = ["yes", "no"]) {
        self.id = id; self.text = text; self.groupId = groupId
        self.isBroadcast = isBroadcast; self.answers = answers
        self.createdAt = createdAt; self.choices = choices
    }

    var answerChoices: [AnswerChoice] {
        choices.compactMap { AnswerChoice(rawValue: $0) }
    }

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
    func send(text: String, to group: KikuGroup, friends: [Friend] = [], choices: [AnswerChoice] = [.yes, .no]) {
        let answers  = group.memberIds.map { Answer(memberId: $0, value: "pending") }
        let question = Question(text: text, groupId: group.id, answers: answers,
                                choices: choices.map(\.rawValue))
        questions.append(question)

        for memberId in group.memberIds {
            let friend = friends.first { $0.id == memberId }
            NotificationManager.shared.scheduleQuestion(
                questionId:   question.id,
                memberId:     memberId,
                memberName:   friend?.name  ?? "メンバー",
                memberEmoji:  friend?.emoji ?? "👤",
                questionText: text,
                choices:      choices
            )
        }
    }

    // 全体送信（全友達へ）
    func sendBroadcast(text: String, to friends: [Friend], choices: [AnswerChoice] = [.yes, .no]) {
        let answers  = friends.map { Answer(memberId: $0.id, value: "pending") }
        let question = Question(text: text, groupId: nil, isBroadcast: true, answers: answers,
                                choices: choices.map(\.rawValue))
        questions.append(question)

        for friend in friends {
            NotificationManager.shared.scheduleQuestion(
                questionId:   question.id,
                memberId:     friend.id,
                memberName:   friend.name,
                memberEmoji:  friend.emoji,
                questionText: text,
                choices:      choices
            )
        }
    }

    // 外部から注入するコールバック・ストア
    // コールバック引数: (questionId, memberId, questionText, answerValue)
    var onAnswered: ((UUID, UUID, String, String) -> Void)?
    var pointStore: PointStore?

    func submit(questionId: UUID, memberId: UUID, value: String) {
        guard let idx = questions.firstIndex(where: { $0.id == questionId }),
              let aidx = questions[idx].answers.firstIndex(where: { $0.memberId == memberId })
        else { return }

        let now = Date()
        questions[idx].answers[aidx].value      = value
        questions[idx].answers[aidx].answeredAt = now

        let question = questions[idx]

        // ポイント付与：質問送信からの経過時間で決定
        let elapsed = now.timeIntervalSince(question.createdAt)
        pointStore?.add(
            questionId:   questionId,
            memberId:     memberId,
            questionText: question.text,
            elapsed:      elapsed
        )

        onAnswered?(questionId, memberId, question.text, value)

        // App Groups経由の未処理回答もここで取り込む
        applyPendingFromSharedStore()
    }

    // App GroupsのUserDefaultsから未処理の回答を取り込む
    func applyPendingFromSharedStore() {
        guard let defaults = UserDefaults(suiteName: "group.com.yukichi.kiku") else { return }
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("answer.") }
        for key in keys {
            let parts = key.split(separator: ".").map(String.init)
            guard parts.count == 3,
                  let qid = UUID(uuidString: parts[1]),
                  let mid = UUID(uuidString: parts[2]),
                  let value = defaults.string(forKey: key) else { continue }
            defaults.removeObject(forKey: key)
            if let idx = questions.firstIndex(where: { $0.id == qid }),
               let aidx = questions[idx].answers.firstIndex(where: { $0.memberId == mid }),
               questions[idx].answers[aidx].value == "pending" {
                let now = Date()
                questions[idx].answers[aidx].value      = value
                questions[idx].answers[aidx].answeredAt = now
                let q = questions[idx]
                let elapsed = now.timeIntervalSince(q.createdAt)
                pointStore?.add(
                    questionId:   qid,
                    memberId:     mid,
                    questionText: q.text,
                    elapsed:      elapsed
                )
                onAnswered?(qid, mid, q.text, value)
            }
        }
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

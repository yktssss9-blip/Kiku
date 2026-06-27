import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - ヘルパー

/// "HH:mm" 形式の時刻値かどうかを判定する
func isTimeValue(_ value: String) -> Bool {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
          parts[0].count <= 2, parts[1].count == 2,
          let h = Int(parts[0]), let m = Int(parts[1]),
          (0...23).contains(h), (0...59).contains(m)
    else { return false }
    return true
}

struct Answer: Codable {
    var memberId: UUID
    var value: String       // "yes" / "no" / "pending"
    var answeredAt: Date?
    /// 一度だけ許可される回答変更を使用済みかどうか
    var hasBeenEdited: Bool = false

    enum CodingKeys: String, CodingKey {
        case memberId, value, answeredAt, hasBeenEdited
    }
    init(memberId: UUID, value: String, answeredAt: Date? = nil, hasBeenEdited: Bool = false) {
        self.memberId = memberId
        self.value = value
        self.answeredAt = answeredAt
        self.hasBeenEdited = hasBeenEdited
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberId      = try c.decode(UUID.self, forKey: .memberId)
        value         = try c.decode(String.self, forKey: .value)
        answeredAt    = try c.decodeIfPresent(Date.self, forKey: .answeredAt)
        hasBeenEdited = try c.decodeIfPresent(Bool.self, forKey: .hasBeenEdited) ?? false
    }
}

struct Question: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var groupId: UUID?
    var answers: [Answer]
    var createdAt: Date = Date()
    var choices: [String] = ["yes", "no"]
    var inviteToken: String = UUID().uuidString
    var memo: String?
    /// 質問の作成者UID（受信質問のチャット解放先を判定するために必要。自分が送った質問では常に自分のUID）
    var createdBy: String?
    /// Firestore の memberNames マップ（memberId → 表示名）。招待リンク経由の回答者名を保持
    var memberNames: [UUID: String] = [:]

    enum CodingKeys: String, CodingKey {
        case id, text, groupId, answers, createdAt, choices, inviteToken, memo, createdBy, memberNames
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,     forKey: .id)
        text        = try c.decode(String.self,   forKey: .text)
        groupId     = try c.decodeIfPresent(UUID.self,    forKey: .groupId)
        answers     = try c.decode([Answer].self, forKey: .answers)
        createdAt   = try c.decodeIfPresent(Date.self,    forKey: .createdAt) ?? Date()
        choices     = try c.decodeIfPresent([String].self, forKey: .choices) ?? ["yes", "no"]
        inviteToken = try c.decodeIfPresent(String.self,  forKey: .inviteToken) ?? UUID().uuidString
        memo        = try c.decodeIfPresent(String.self,  forKey: .memo)
        createdBy   = try c.decodeIfPresent(String.self,  forKey: .createdBy)
        if let raw  = try c.decodeIfPresent([String: String].self, forKey: .memberNames) {
            memberNames = raw.reduce(into: [:]) { dict, pair in
                if let uuid = UUID(uuidString: pair.key) { dict[uuid] = pair.value }
            }
        }
    }
    init(id: UUID = UUID(), text: String, groupId: UUID? = nil,
         answers: [Answer], createdAt: Date = Date(), choices: [String] = ["yes", "no"],
         inviteToken: String = UUID().uuidString, memo: String? = nil, createdBy: String? = nil,
         memberNames: [UUID: String] = [:]) {
        self.id = id; self.text = text; self.groupId = groupId
        self.answers = answers; self.createdAt = createdAt; self.choices = choices
        self.inviteToken = inviteToken; self.memo = memo; self.createdBy = createdBy
        self.memberNames = memberNames
    }

    var answerChoices: [AnswerChoice] {
        choices.compactMap { AnswerChoice(rawValue: $0) }
    }

    var isCompleted: Bool {
        !answers.isEmpty && answers.allSatisfy { $0.value != "pending" }
    }

    func summary() -> (yes: Int, no: Int, pending: Int) {
        var yes = 0, no = 0, pending = 0
        for a in answers {
            let v = a.value
            if v == "pending"        { pending += 1 }
            else if answerIsNo(v)    { no      += 1 }
            else                     { yes     += 1 }
        }
        return (yes, no, pending)
    }
}

class QuestionStore: ObservableObject {
    @Published var questions: [Question] = [] {
        didSet {
            if !isUpdatingFromFirestore { save() }
        }
    }

    /// 他ユーザーから届いた質問（Firestoreが正・ローカル永続化なし）
    @Published var receivedQuestions: [Question] = []

    /// 受信質問ごとの自分の memberId（questionId → memberId）
    @Published var receivedMemberMap: [UUID: UUID] = [:]

    private let key = "kiku.questions"
    private let db  = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var receivedListener: ListenerRegistration?
    private var isUpdatingFromFirestore = false
    private var detectedReceivedIds: Set<UUID> = []
    private var isInitialReceivedLoad = true
    private let completionNotifiedKey = "kiku.completionNotifiedIds"
    private var notifiedCompletionIds: Set<UUID> = []

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Question].self, from: data) {
            questions = decoded
        }
        if let ids = UserDefaults.standard.stringArray(forKey: completionNotifiedKey) {
            notifiedCompletionIds = Set(ids.compactMap { UUID(uuidString: $0) })
        }
        purgeOldCompleted()
    }

    // MARK: - Firestore リスナー

    func startListening(forUID uid: String) {
        stopListening()
        listener = db.collection("questions")
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

    /// 他ユーザーから自分宛に届いた質問をリッスン
    func startListeningReceived(forUID uid: String) {
        stopListeningReceived()
        isInitialReceivedLoad = true
        detectedReceivedIds.removeAll()
        receivedListener = db.collection("questions")
            .whereField("recipientUIDs", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.mergeReceivedFromFirestore(snapshot, forUID: uid)
            }
    }

    func stopListeningReceived() {
        receivedListener?.remove()
        receivedListener = nil
    }

    func refresh(forUID uid: String) async {
        stopListening()
        stopListeningReceived()
        startListening(forUID: uid)
        startListeningReceived(forUID: uid)
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private func mergeReceivedFromFirestore(_ snapshot: QuerySnapshot, forUID uid: String) {
        var merged = self.receivedQuestions
        var memberMap = self.receivedMemberMap
        var newlyDetected: [(Question, UUID)] = []
        let isInitial = isInitialReceivedLoad
        isInitialReceivedLoad = false

        for change in snapshot.documentChanges {
            let data = change.document.data()
            guard let id = UUID(uuidString: change.document.documentID),
                  let q  = questionFromData(id: id, data: data) else { continue }

            if let idx = merged.firstIndex(where: { $0.id == q.id }) {
                merged[idx] = q
            } else {
                merged.append(q)
            }

            if let recipientMap = data["recipientMemberMap"] as? [String: String],
               let memberIdStr = recipientMap[uid],
               let memberId = UUID(uuidString: memberIdStr) {
                memberMap[q.id] = memberId
            }

            guard change.type == .added else { continue }
            if isInitial {
                detectedReceivedIds.insert(q.id)
                continue
            }
            guard !detectedReceivedIds.contains(q.id),
                  data["createdBy"] as? String != uid,
                  let recipientMap = data["recipientMemberMap"] as? [String: String],
                  let memberIdStr = recipientMap[uid],
                  let memberId = UUID(uuidString: memberIdStr)
            else { continue }
            detectedReceivedIds.insert(q.id)
            newlyDetected.append((q, memberId))
        }

        DispatchQueue.main.async {
            self.receivedMemberMap = memberMap
            self.receivedQuestions = merged
            self.applyPendingFromSharedStore()
            for (q, memberId) in newlyDetected {
                self.onReceivedQuestion?(q, memberId)
            }
        }
    }

    /// Firestoreから取得した質問をローカルにマージ（pending状態は上書きしない・招待回答は追加）
    private func mergeFromFirestore(_ docs: [QueryDocumentSnapshot]) {
        var merged = self.questions
        for doc in docs {
            guard let q = questionFromFirestore(doc) else { continue }
            if let idx = merged.firstIndex(where: { $0.id == q.id }) {
                for fsAnswer in q.answers {
                    if let aidx = merged[idx].answers.firstIndex(where: { $0.memberId == fsAnswer.memberId }) {
                        if merged[idx].answers[aidx].value == "pending" && fsAnswer.value != "pending" {
                            merged[idx].answers[aidx] = fsAnswer
                            if let answeredAt = fsAnswer.answeredAt {
                                let elapsed = answeredAt.timeIntervalSince(merged[idx].createdAt)
                                pointStore?.add(questionId: q.id, memberId: fsAnswer.memberId,
                                                questionText: q.text, elapsed: elapsed)
                            }
                        }
                    } else {
                        // 招待リンク経由で追加された回答をマージ
                        merged[idx].answers.append(fsAnswer)
                    }
                }
                merged[idx].memberNames.merge(q.memberNames) { _, new in new }
            } else {
                merged.append(q)
            }
        }
        let newlyCompleted = merged.filter { newQ in
            newQ.isCompleted &&
            !self.notifiedCompletionIds.contains(newQ.id) &&
            !(self.questions.first { $0.id == newQ.id }?.isCompleted ?? false)
        }
        let updatedQuestions = merged.filter { newQ in
            self.questions.first { $0.id == newQ.id }?.summary().pending != newQ.summary().pending
        }
        DispatchQueue.main.async {
            self.isUpdatingFromFirestore = true
            self.questions = merged
            self.isUpdatingFromFirestore = false
            for q in newlyCompleted {
                self.markCompletionNotified(q.id)
                NotificationCenter.default.post(name: .kikuQuestionCompleted, object: q)
                NotificationManager.shared.scheduleCompletion(question: q)
            }
            Task { @MainActor in
                for q in updatedQuestions {
                    await ActivityManager.shared.update(questionId: q.id, summary: q.summary())
                }
            }
        }
    }

    // MARK: - 質問送信

    func send(text: String, to group: KikuGroup, friends: [Friend] = [], choices: [AnswerChoice] = [.yes, .no], memo: String? = nil, reminderAfter: TimeInterval? = nil, includeSelf: Bool = false) {
        var memberIds = group.memberIds
        if includeSelf, let selfId = senderMemberId, !memberIds.contains(selfId) {
            memberIds.append(selfId)
        }
        let answers  = memberIds.map { Answer(memberId: $0, value: "pending") }
        let question = Question(text: text, groupId: group.id, answers: answers,
                                choices: choices.map(\.rawValue), memo: memo,
                                createdBy: Auth.auth().currentUser?.uid)
        questions.append(question)
        saveQuestionToFirestore(question, friends: friends)
        NotificationManager.playOutgoingSound()

        if includeSelf, let selfId = senderMemberId, memberIds.contains(selfId) {
            NotificationManager.shared.scheduleQuestion(
                questionId:   question.id,
                memberId:     selfId,
                memberName:   senderName,
                memberEmoji:  senderEmoji,
                questionText: text,
                choices:      choices
            )
            if let seconds = reminderAfter {
                NotificationManager.shared.scheduleAutoReminder(
                    questionId:   question.id,
                    memberId:     selfId,
                    memberName:   senderName,
                    memberEmoji:  senderEmoji,
                    questionText: text,
                    choices:      choices,
                    afterSeconds: seconds
                )
            }
        }
    }

    func sendToIndividuals(text: String, to friends: [Friend], choices: [AnswerChoice] = [.yes, .no], memo: String? = nil, reminderAfter: TimeInterval? = nil) {
        let answers  = friends.map { Answer(memberId: $0.id, value: "pending") }
        let question = Question(text: text, groupId: nil, answers: answers,
                                choices: choices.map(\.rawValue), memo: memo,
                                createdBy: Auth.auth().currentUser?.uid)
        questions.append(question)
        saveQuestionToFirestore(question, friends: friends)
        NotificationManager.playOutgoingSound()
    }

    /// 招待リンク専用で質問を作成（メンバーなし）。作成した Question を返す
    func sendViaLink(text: String, choices: [AnswerChoice] = [.yes, .no]) -> Question {
        let question = Question(text: text, groupId: nil, answers: [],
                                choices: choices.map(\.rawValue),
                                createdBy: Auth.auth().currentUser?.uid)
        questions.append(question)
        saveQuestionToFirestore(question, friends: [])
        NotificationManager.playOutgoingSound()
        return question
    }

    // MARK: - 回答処理

    var onAnswered: ((UUID, UUID, String, String) -> Void)?
    /// 回答が変更された際に呼ばれる（questionId, memberId, questionText, oldValue, newValue）
    var onAnswerEdited: ((UUID, UUID, String, String, String) -> Void)?
    var onReceivedQuestion: ((Question, UUID) -> Void)?
    var pointStore: PointStore?
    var senderMemberId: UUID?
    var senderName: String = ""
    var senderEmoji: String = ""

    func submit(questionId: UUID, memberId: UUID, value: String) {
        guard let idx  = questions.firstIndex(where: { $0.id == questionId }),
              let aidx = questions[idx].answers.firstIndex(where: { $0.memberId == memberId })
        else { return }
        guard questions[idx].answers[aidx].value == "pending" else { return }

        let now = Date()
        questions[idx].answers[aidx].value      = value
        questions[idx].answers[aidx].answeredAt = now

        NotificationManager.shared.cancelAutoReminder(questionId: questionId, memberId: memberId)

        let question = questions[idx]
        let elapsed  = now.timeIntervalSince(question.createdAt)
        pointStore?.add(questionId: questionId, memberId: memberId,
                        questionText: question.text, elapsed: elapsed)
        if let senderId = senderMemberId {
            pointStore?.addSenderBonus(questionId: questionId, senderMemberId: senderId,
                                       questionText: question.text, elapsed: elapsed)
        }
        onAnswered?(questionId, memberId, question.text, value)

        if questions[idx].isCompleted && !notifiedCompletionIds.contains(questionId) {
            markCompletionNotified(questionId)
            let completedQ = questions[idx]
            NotificationCenter.default.post(name: .kikuQuestionCompleted, object: completedQ)
            NotificationManager.shared.scheduleCompletion(question: completedQ)
        }

        updateAnswerInFirestore(questionId: questionId, memberId: memberId,
                                value: value, answeredAt: now)
        Task { @MainActor in
            await ActivityManager.shared.end(questionId: questionId, memberId: memberId)
            let s = self.questions[idx].summary()
            if s.pending > 0 {
                await ActivityManager.shared.update(questionId: questionId, summary: s)
            }
        }
        applyPendingFromSharedStore()
    }

    /// 一度だけ許可される回答の変更（ポイントは無効化され、Live Activity等の副作用は発生しない）
    func editAnswer(questionId: UUID, memberId: UUID, newValue: String) {
        guard let idx  = questions.firstIndex(where: { $0.id == questionId }),
              let aidx = questions[idx].answers.firstIndex(where: { $0.memberId == memberId })
        else { return }
        let answer = questions[idx].answers[aidx]
        guard answer.value != "pending", !answer.hasBeenEdited else { return }

        let oldValue = answer.value
        guard let answeredAt = answer.answeredAt else { return }

        questions[idx].answers[aidx].value         = newValue
        questions[idx].answers[aidx].hasBeenEdited = true

        let question = questions[idx]
        onAnswerEdited?(questionId, memberId, question.text, oldValue, newValue)

        updateAnswerInFirestore(questionId: questionId, memberId: memberId,
                                value: newValue, answeredAt: answeredAt, hasBeenEdited: true)
    }

    /// 受信質問への回答（フル機能：ポイント加算・チャット解放を行う）
    func submitReceived(questionId: UUID, memberId: UUID, value: String) {
        guard let idx  = receivedQuestions.firstIndex(where: { $0.id == questionId }),
              let aidx = receivedQuestions[idx].answers.firstIndex(where: { $0.memberId == memberId }),
              receivedQuestions[idx].answers[aidx].value == "pending"
        else { return }

        let now = Date()
        receivedQuestions[idx].answers[aidx].value      = value
        receivedQuestions[idx].answers[aidx].answeredAt = now

        let question = receivedQuestions[idx]
        let elapsed  = now.timeIntervalSince(question.createdAt)
        pointStore?.add(questionId: questionId, memberId: memberId,
                        questionText: question.text, elapsed: elapsed)
        onAnswered?(questionId, memberId, question.text, value)

        updateAnswerInFirestore(questionId: questionId, memberId: memberId,
                                value: value, answeredAt: now)
        Task { @MainActor in
            await ActivityManager.shared.end(questionId: questionId, memberId: memberId)
        }
    }

    func applyPendingFromSharedStore() {
        guard let defaults = UserDefaults(suiteName: "group.com.yukichi.kiku") else { return }
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("answer.") && !$0.hasPrefix("answer_ts.") }
        for key in keys {
            let parts = key.split(separator: ".").map(String.init)
            guard parts.count == 3,
                  let qid   = UUID(uuidString: parts[1]),
                  let mid   = UUID(uuidString: parts[2]),
                  let value = defaults.string(forKey: key) else { continue }
            let tsKey = "answer_ts.\(parts[1]).\(parts[2])"
            if let idx  = questions.firstIndex(where: { $0.id == qid }),
               let aidx = questions[idx].answers.firstIndex(where: { $0.memberId == mid }),
               questions[idx].answers[aidx].value == "pending" {
                defaults.removeObject(forKey: key)
                defaults.removeObject(forKey: tsKey)
                let now     = Date()
                questions[idx].answers[aidx].value      = value
                questions[idx].answers[aidx].answeredAt = now
                NotificationManager.shared.cancelAutoReminder(questionId: qid, memberId: mid)
                let q       = questions[idx]
                let elapsed = now.timeIntervalSince(q.createdAt)
                pointStore?.add(questionId: qid, memberId: mid,
                                questionText: q.text, elapsed: elapsed)
                if let senderId = senderMemberId {
                    pointStore?.addSenderBonus(questionId: qid, senderMemberId: senderId,
                                               questionText: q.text, elapsed: elapsed)
                }
                onAnswered?(qid, mid, q.text, value)
                if questions[idx].isCompleted && !notifiedCompletionIds.contains(qid) {
                    markCompletionNotified(qid)
                    let completedQ = questions[idx]
                    NotificationCenter.default.post(name: .kikuQuestionCompleted, object: completedQ)
                    NotificationManager.shared.scheduleCompletion(question: completedQ)
                }
                updateAnswerInFirestore(questionId: qid, memberId: mid,
                                        value: value, answeredAt: now)
                Task { @MainActor in
                    await ActivityManager.shared.end(questionId: qid, memberId: mid)
                    let s = self.questions[idx].summary()
                    if s.pending > 0 {
                        await ActivityManager.shared.update(questionId: qid, summary: s)
                    }
                }
            } else if receivedQuestions.contains(where: { $0.id == qid }) {
                defaults.removeObject(forKey: key)
                defaults.removeObject(forKey: tsKey)
                submitReceived(questionId: qid, memberId: mid, value: value)
            } else {
                let ts = defaults.double(forKey: tsKey)
                if ts > 0 {
                    if Date().timeIntervalSince1970 - ts > 300 {
                        defaults.removeObject(forKey: key)
                        defaults.removeObject(forKey: tsKey)
                    }
                } else {
                    defaults.set(Date().timeIntervalSince1970, forKey: tsKey)
                }
            }
        }
    }

    func delete(questionId: UUID) {
        questions.removeAll { $0.id == questionId }
        db.collection("questions").document(questionId.uuidString).delete()
    }

    func sendReminder(questionId: UUID) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("reminderRequests").addDocument(data: [
            "questionId":   questionId.uuidString,
            "requestedBy":  uid,
            "createdAt":    FieldValue.serverTimestamp()
        ])
    }

    func deleteQuestions(forGroupId groupId: UUID) {
        let targets = questions.filter { $0.groupId == groupId }
        questions.removeAll { $0.groupId == groupId }
        for q in targets {
            db.collection("questions").document(q.id.uuidString).delete()
        }
    }

    func resetAnswer(questionId: UUID, memberId: UUID) {
        guard let idx  = questions.firstIndex(where: { $0.id == questionId }),
              let aidx = questions[idx].answers.firstIndex(where: { $0.memberId == memberId })
        else { return }
        questions[idx].answers[aidx].value      = "pending"
        questions[idx].answers[aidx].answeredAt = nil

        let key = "answers.\(memberId.uuidString)"
        db.collection("questions").document(questionId.uuidString).updateData([
            "\(key).value": "pending",
            "\(key).answeredAt": NSNull()
        ])
    }

    func questions(for group: KikuGroup) -> [Question] {
        questions.filter { $0.groupId == group.id }
                 .sorted { $0.createdAt > $1.createdAt }
    }

    func purgeOldCompleted(olderThan days: Int = 30) {
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let before = questions.count
        questions.removeAll { $0.isCompleted && $0.createdAt < threshold }
        let removed = before - questions.count
        if removed > 0 {
            print("[QuestionStore] 自動削除: 完了済み古い質問を \(removed) 件削除しました")
        }
    }

    private func markCompletionNotified(_ questionId: UUID) {
        notifiedCompletionIds.insert(questionId)
        let ids = notifiedCompletionIds.map(\.uuidString)
        UserDefaults.standard.set(ids, forKey: completionNotifiedKey)
    }

    // MARK: - Firestore データ変換

    private func saveQuestionToFirestore(_ question: Question, friends: [Friend] = []) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("questions").document(question.id.uuidString)
            .setData(firestoreData(for: question, uid: uid, friends: friends))
    }

    private func updateAnswerInFirestore(questionId: UUID, memberId: UUID,
                                         value: String, answeredAt: Date, hasBeenEdited: Bool? = nil) {
        let prefix = "answers.\(memberId.uuidString)"
        var data: [String: Any] = [
            "\(prefix).value":      value,
            "\(prefix).answeredAt": Timestamp(date: answeredAt)
        ]
        if let hasBeenEdited { data["\(prefix).hasBeenEdited"] = hasBeenEdited }
        db.collection("questions").document(questionId.uuidString).updateData(data)
    }

    private func firestoreData(for question: Question, uid: String, friends: [Friend] = []) -> [String: Any] {
        var answersDict: [String: Any] = [:]
        for a in question.answers {
            answersDict[a.memberId.uuidString] = [
                "value":         a.value,
                "answeredAt":    a.answeredAt.map { Timestamp(date: $0) } as Any,
                "hasBeenEdited": a.hasBeenEdited
            ]
        }
        var dict: [String: Any] = [
            "text":        question.text,
            "groupId":     question.groupId?.uuidString as Any,
            "choices":     question.choices,
            "createdAt":   Timestamp(date: question.createdAt),
            "createdBy":   uid,
            "inviteToken": question.inviteToken,
            "answers":     answersDict
        ]
        let memberNamesDict = friends
            .filter { f in question.answers.contains { $0.memberId == f.id } }
            .reduce(into: [String: Any]()) { $0[$1.id.uuidString] = $1.name }
        if !memberNamesDict.isEmpty { dict["memberNames"] = memberNamesDict }
        let recipientUIDs = friends
            .filter { f in question.answers.contains { $0.memberId == f.id } && !f.firebaseUID.isEmpty }
            .map(\.firebaseUID)
        if !recipientUIDs.isEmpty { dict["recipientUIDs"] = recipientUIDs }
        let recipientMemberMap = friends
            .filter { f in question.answers.contains { $0.memberId == f.id } && !f.firebaseUID.isEmpty }
            .reduce(into: [String: Any]()) { $0[$1.firebaseUID] = $1.id.uuidString }
        if !recipientMemberMap.isEmpty { dict["recipientMemberMap"] = recipientMemberMap }
        if let memo = question.memo, !memo.isEmpty { dict["memo"] = memo }
        return dict
    }

    private func questionFromData(id: UUID, data: [String: Any]) -> Question? {
        guard let text = data["text"] as? String,
              let answersDict = data["answers"] as? [String: Any] else { return nil }

        let groupId     = (data["groupId"] as? String).flatMap { UUID(uuidString: $0) }
        let choices     = data["choices"] as? [String] ?? ["yes", "no"]
        let createdAt   = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let inviteToken = data["inviteToken"] as? String ?? UUID().uuidString
        let memo        = data["memo"] as? String
        let createdBy   = data["createdBy"] as? String

        let answers: [Answer] = answersDict.compactMap { key, val in
            guard let memberId = UUID(uuidString: key),
                  let valDict  = val as? [String: Any],
                  let value    = valDict["value"] as? String else { return nil }
            let answeredAt    = (valDict["answeredAt"] as? Timestamp)?.dateValue()
            let hasBeenEdited = valDict["hasBeenEdited"] as? Bool ?? false
            return Answer(memberId: memberId, value: value, answeredAt: answeredAt, hasBeenEdited: hasBeenEdited)
        }

        var memberNames: [UUID: String] = [:]
        if let rawNames = data["memberNames"] as? [String: String] {
            for (key, name) in rawNames {
                if let uuid = UUID(uuidString: key) { memberNames[uuid] = name }
            }
        }

        return Question(id: id, text: text, groupId: groupId, answers: answers,
                        createdAt: createdAt, choices: choices, inviteToken: inviteToken, memo: memo,
                        createdBy: createdBy, memberNames: memberNames)
    }

    private func questionFromFirestore(_ doc: QueryDocumentSnapshot) -> Question? {
        guard let id = UUID(uuidString: doc.documentID) else { return nil }
        return questionFromData(id: id, data: doc.data())
    }

    // MARK: - 招待リンク

    func fetchQuestionForInvite(questionId: UUID, token: String) async -> Question? {
        guard let doc = try? await db.collection("questions").document(questionId.uuidString).getDocument(),
              doc.exists,
              let data = doc.data(),
              let storedToken = data["inviteToken"] as? String,
              storedToken == token else { return nil }
        return questionFromData(id: questionId, data: data)
    }

    func submitInviteAnswer(questionId: UUID, memberId: UUID, value: String) {
        let now = Date()
        let prefix = "answers.\(memberId.uuidString)"
        db.collection("questions").document(questionId.uuidString).updateData([
            "\(prefix).value":      value,
            "\(prefix).answeredAt": Timestamp(date: now)
        ])
    }

    // MARK: - ローカル永続化

    private func save() {
        if let data = try? JSONEncoder().encode(questions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

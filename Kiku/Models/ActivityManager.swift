import ActivityKit
import KikuShared
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
class ActivityManager: ObservableObject {
    static let shared = ActivityManager()

    @Published var lastError: String? = nil
    var isActive: Bool { !Activity<KikuActivityAttributes>.activities.isEmpty }

    private var pushToStartTask: Task<Void, Never>? = nil

    func cleanupStaleActivities() async {
        for activity in Activity<KikuActivityAttributes>.activities {
            let age = Date().timeIntervalSince(activity.attributes.sentAt)
            if activity.activityState == .stale || activity.activityState == .ended || age > 1800 {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        for activity in Activity<FriendRequestActivityAttributes>.activities {
            let age = Date().timeIntervalSince(activity.attributes.sentAt)
            if activity.activityState == .stale || activity.activityState == .ended || age > 86400 {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func observePushToStartToken() {
        pushToStartTask?.cancel()
        pushToStartTask = Task {
            await cleanupStaleActivities()

            if #available(iOS 17.2, *) {
                for await data in Activity<KikuActivityAttributes>.pushToStartTokenUpdates {
                    let hex = data.map { String(format: "%02x", $0) }.joined()
                    guard let uid = Auth.auth().currentUser?.uid else { continue }
                    do {
                        try await Firestore.firestore().collection("users").document(uid)
                            .setData(["liveActivityPushToStartToken": hex], merge: true)
                        print("[LiveActivity] push-to-startトークン保存成功: \(hex.prefix(20))...")
                    } catch {
                        print("[LiveActivity] push-to-startトークン保存失敗: \(error)")
                    }
                }
            }
        }
    }

    func startFromPush(questionId: String, questionText: String, totalCount: Int,
                       memberId: String, memberName: String, choices: [String]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let alreadyExists = Activity<KikuActivityAttributes>.activities.contains {
            $0.attributes.questionId == questionId && $0.attributes.memberId == memberId
        }
        if alreadyExists { return }

        Task {
            let attributes = KikuActivityAttributes(
                questionId: questionId, questionText: questionText, totalCount: totalCount,
                memberId: memberId, memberName: memberName, sentAt: Date(), choices: choices
            )
            let state = KikuActivityAttributes.ContentState(
                yesCount: 0, noCount: 0, pendingCount: totalCount
            )
            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: Date().addingTimeInterval(600), relevanceScore: 1.0),
                    pushType: .token
                )
                lastError = nil
                print("✅ Live Activity started from push: \(activity.id)")
            } catch {
                print("❌ Live Activity from push error: \(error)")
            }
        }
    }

    func start(question: Question, memberId: UUID, memberName: String, choices: [String]? = nil) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Live Activityが無効です。設定 → 通知 → Kiku → Live Activityをオンにしてください"
            return
        }

        let qid = question.id.uuidString
        let mid = memberId.uuidString
        let alreadyExists = Activity<KikuActivityAttributes>.activities.contains {
            $0.attributes.questionId == qid && $0.attributes.memberId == mid
        }
        if alreadyExists { return }

        Task {
            await requestNew(question: question, memberId: memberId, memberName: memberName, choices: choices ?? question.answerChoices.map(\.rawValue))
        }
    }

    private func requestNew(question: Question, memberId: UUID, memberName: String, choices: [String]) async {
        let s = question.summary()
        let attributes = KikuActivityAttributes(
            questionId:   question.id.uuidString,
            questionText: question.text,
            totalCount:   question.answers.count,
            memberId:     memberId.uuidString,
            memberName:   memberName,
            sentAt:       Date(),
            choices:      choices
        )
        let state = KikuActivityAttributes.ContentState(
            yesCount: s.yes, noCount: s.no, pendingCount: s.pending
        )
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(
                    state:          state,
                    staleDate:      Date().addingTimeInterval(600),
                    relevanceScore: 1.0
                ),
                pushType: .token
            )
            lastError = nil
            print("✅ Live Activity started: \(activity.id)")
        } catch {
            lastError = "起動失敗: \(error.localizedDescription)"
            print("❌ Live Activity error: \(error)")
        }
    }

    func update(questionId: UUID, summary: (yes: Int, no: Int, pending: Int)) async {
        for activity in Activity<KikuActivityAttributes>.activities
            where activity.attributes.questionId == questionId.uuidString {
            let newState = KikuActivityAttributes.ContentState(
                yesCount: summary.yes, noCount: summary.no, pendingCount: summary.pending
            )
            await activity.update(.init(state: newState, staleDate: Date().addingTimeInterval(600)))
        }
    }

    func end(questionId: UUID) async {
        for activity in Activity<KikuActivityAttributes>.activities
            where activity.attributes.questionId == questionId.uuidString {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if Activity<KikuActivityAttributes>.activities.isEmpty {
            observePushToStartToken()
        }
    }

    func end(questionId: UUID, memberId: UUID) async {
        for activity in Activity<KikuActivityAttributes>.activities
            where activity.attributes.questionId == questionId.uuidString
               && activity.attributes.memberId   == memberId.uuidString {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if Activity<KikuActivityAttributes>.activities.isEmpty {
            observePushToStartToken()
        }
    }

    func endAll() async {
        for activity in Activity<KikuActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        observePushToStartToken()
    }

    // MARK: - 友達申請 Live Activity

    func startFriendRequest(requestId: String, fromUID: String, fromName: String, fromEmoji: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            for activity in Activity<FriendRequestActivityAttributes>.activities
                where activity.attributes.requestId == requestId {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            let attributes = FriendRequestActivityAttributes(
                requestId: requestId,
                fromUID:   fromUID,
                fromName:  fromName,
                fromEmoji: fromEmoji,
                sentAt:    Date()
            )
            let state = FriendRequestActivityAttributes.ContentState(status: "pending")
            do {
                let _ = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: Date().addingTimeInterval(86400), relevanceScore: 0.8)
                )
                print("✅ FriendRequest Live Activity started: \(requestId.prefix(8))")
            } catch {
                print("❌ FriendRequest Live Activity error: \(error)")
            }
        }
    }

    func endFriendRequest(requestId: String) async {
        for activity in Activity<FriendRequestActivityAttributes>.activities
            where activity.attributes.requestId == requestId {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func applyPendingAnswers(to store: QuestionStore) {
        let pending = SharedStore.popPendingAnswers()
        for item in pending {
            guard let qid = UUID(uuidString: item.questionId),
                  let mid = UUID(uuidString: item.memberId) else { continue }
            store.submit(questionId: qid, memberId: mid, value: item.value)
        }
    }
}

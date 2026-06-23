import ActivityKit
import KikuShared
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
class ActivityManager: ObservableObject {
    static let shared = ActivityManager()

    @Published var lastError: String? = nil
    @Published var isActive: Bool = false

    private var pushToStartTask: Task<Void, Never>? = nil

    // push-to-startトークンを購読し、/users/{uid}.liveActivityPushToStartToken に保存
    func observePushToStartToken() {
        pushToStartTask?.cancel()
        pushToStartTask = Task {
            if #available(iOS 17.2, *) {
                for await data in Activity<KikuActivityAttributes>.pushToStartTokenUpdates {
                    let hex = data.map { String(format: "%02x", $0) }.joined()
                    guard let uid = Auth.auth().currentUser?.uid else { continue }
                    try? await Firestore.firestore().collection("users").document(uid)
                        .setData(["liveActivityPushToStartToken": hex], merge: true)
                    print("[LiveActivity] push-to-startトークン保存: \(hex.prefix(20))...")
                }
            }
        }
    }

    func start(question: Question, memberId: UUID, memberName: String, choices: [String]? = nil) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Live Activityが無効です。設定 → 通知 → Kiku → Live Activityをオンにしてください"
            return
        }

        // 同じ質問・同じメンバーの既存Activityのみ終了（他メンバー分は維持）
        Task {
            for activity in Activity<KikuActivityAttributes>.activities
                where activity.attributes.questionId == question.id.uuidString
                   && activity.attributes.memberId   == memberId.uuidString {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
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
                    staleDate:      Date().addingTimeInterval(600), // 10分間 fresh 維持
                    relevanceScore: 1.0                              // 最高優先度で一番上に表示
                ),
                pushType: nil
            )
            isActive = true
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
            await activity.update(.init(state: newState, staleDate: nil))
        }
    }

    // 質問全体のActivityを終了
    func end(questionId: UUID) async {
        for activity in Activity<KikuActivityAttributes>.activities
            where activity.attributes.questionId == questionId.uuidString {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        isActive = false
    }

    // 特定メンバーのActivityを終了（回答後に呼ぶ）
    func end(questionId: UUID, memberId: UUID) async {
        for activity in Activity<KikuActivityAttributes>.activities
            where activity.attributes.questionId == questionId.uuidString
               && activity.attributes.memberId   == memberId.uuidString {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // すべてのActivityを終了（アカウント削除時に呼ぶ）
    func endAll() async {
        for activity in Activity<KikuActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        isActive = false
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

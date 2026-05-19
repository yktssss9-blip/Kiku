import ActivityKit
import SwiftUI

@MainActor
class ActivityManager: ObservableObject {
    static let shared = ActivityManager()

    @Published var lastError: String? = nil
    @Published var isActive: Bool = false

    func start(question: Question, memberId: UUID, memberName: String) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Live Activityが無効です。設定 → 通知 → きく → Live Activityをオンにしてください"
            return
        }

        // 既存のActivityをすべて終了してから新しく起動
        Task {
            for activity in Activity<KikuActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            await requestNew(question: question, memberId: memberId, memberName: memberName)
        }
    }

    private func requestNew(question: Question, memberId: UUID, memberName: String) async {
        let s = question.summary()
        let attributes = KikuActivityAttributes(
            questionId:   question.id.uuidString,
            questionText: question.text,
            totalCount:   question.answers.count,
            memberId:     memberId.uuidString,
            memberName:   memberName,
            sentAt:       Date()
        )
        let state = KikuActivityAttributes.ContentState(
            yesCount: s.yes, noCount: s.no, pendingCount: s.pending
        )
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
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

    func end(questionId: UUID) async {
        for activity in Activity<KikuActivityAttributes>.activities
            where activity.attributes.questionId == questionId.uuidString {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        isActive = false
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

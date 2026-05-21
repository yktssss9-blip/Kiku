import UserNotifications
import Foundation

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let categoryId   = "KIKU_QUESTION"
    static let yesActionId  = "ANSWER_YES"
    static let noActionId   = "ANSWER_NO"

    // 長押しボタンで回答したとき
    var onAnswer: ((UUID, UUID, String) -> Void)?

    // 通知本文をタップしてAnswerViewを開くとき
    var onOpenAnswer: ((UUID, UUID) -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    // MARK: - カテゴリ登録

    func registerCategories() {
        let yesAction = UNNotificationAction(
            identifier: Self.yesActionId,
            title: "✅ はい",
            options: []          // アプリを開かずにバックグラウンドで処理
        )
        let noAction = UNNotificationAction(
            identifier: Self.noActionId,
            title: "❌ いいえ",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [yesAction, noAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - 通知スケジュール

    func scheduleQuestion(
        questionId: UUID,
        memberId: UUID,
        memberName: String,
        memberEmoji: String,
        questionText: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "\(memberEmoji) \(memberName)さんへ質問が届きました"
        content.body  = questionText
        content.sound = .default
        content.categoryIdentifier  = Self.categoryId
        content.interruptionLevel   = .active
        content.userInfo = [
            "questionId": questionId.uuidString,
            "memberId":   memberId.uuidString
        ]

        let trigger    = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "kiku-\(questionId.uuidString)-\(memberId.uuidString)"
        let request    = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 通知タップ処理

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo
        guard
            let qIdStr     = userInfo["questionId"] as? String,
            let mIdStr     = userInfo["memberId"]   as? String,
            let questionId = UUID(uuidString: qIdStr),
            let memberId   = UUID(uuidString: mIdStr)
        else { return }

        switch response.actionIdentifier {
        case Self.yesActionId:
            // 長押し「はい」→ 直接記録
            onAnswer?(questionId, memberId, "yes")

        case Self.noActionId:
            // 長押し「いいえ」→ 直接記録
            onAnswer?(questionId, memberId, "no")

        case UNNotificationDefaultActionIdentifier:
            // 通知本文タップ → AnswerView を表示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.onOpenAnswer?(questionId, memberId)
            }

        default:
            break
        }
    }

    // アプリ起動中も通知をバナーで表示
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

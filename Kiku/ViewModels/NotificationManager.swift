import UserNotifications
import Foundation
import AudioToolbox

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    // 長押しボタンで回答したとき
    var onAnswer: ((UUID, UUID, String) -> Void)?

    // 通知本文をタップして AnswerView を開くとき
    var onOpenAnswer: ((UUID, UUID) -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - 送信音

    /// 質問を送信したタイミングで一度だけ鳴らす効果音（iMessage 送信音）
    static func playOutgoingSound() {
        AudioServicesPlaySystemSound(1002)
    }

    // MARK: - 動的カテゴリ登録

    /// choices の組み合わせからカテゴリ ID を生成（ソート済みで一意）
    static func categoryId(for choices: [AnswerChoice]) -> String {
        "KIKU_" + choices.map(\.rawValue).sorted().joined(separator: "_")
    }

    /// 指定された choices に対応するカテゴリを登録（既存カテゴリとマージ）
    func registerCategory(for choices: [AnswerChoice]) {
        let newCategory = UNNotificationCategory(
            identifier: Self.categoryId(for: choices),
            actions: choices.map { $0.makeNotificationAction() },
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var updated = existing.filter {
                $0.identifier != newCategory.identifier   // 同 ID は上書き
            }
            updated.insert(newCategory)
            UNUserNotificationCenter.current().setNotificationCategories(updated)
        }
    }

    // MARK: - 通知スケジュール

    func scheduleQuestion(
        questionId:   UUID,
        memberId:     UUID,
        memberName:   String,
        memberEmoji:  String,
        questionText: String,
        choices:      [AnswerChoice] = [.yes, .no]
    ) {
        registerCategory(for: choices)

        let content = UNMutableNotificationContent()
        content.title               = "\(memberEmoji) \(memberName)さんへ質問が届きました"
        content.body                = questionText
        content.sound               = .default
        content.categoryIdentifier  = Self.categoryId(for: choices)
        content.interruptionLevel   = .active
        content.userInfo            = [
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

        let actionId = response.actionIdentifier

        switch actionId {
        case AnswerChoice.yes.actionId:
            onAnswer?(questionId, memberId, "yes")

        case AnswerChoice.no.actionId:
            onAnswer?(questionId, memberId, "no")

        case AnswerChoice.time.actionId, AnswerChoice.freeText.actionId:
            // テキスト入力アクション
            if let textResponse = response as? UNTextInputNotificationResponse {
                let text = textResponse.userText.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    onAnswer?(questionId, memberId, text)
                }
            }

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

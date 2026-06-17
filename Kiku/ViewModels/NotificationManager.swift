import UserNotifications
import Intents
import UIKit
import Foundation
import AudioToolbox

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let friendRequestCategoryId = "FRIEND_REQUEST"
    static let friendRequestAcceptId   = "FRIEND_REQUEST_ACCEPT"
    static let friendRequestDeclineId  = "FRIEND_REQUEST_DECLINE"
    static let chatCategoryId          = "CHAT_MESSAGE"

    // 長押しボタンで回答したとき
    var onAnswer: ((UUID, UUID, String) -> Void)?

    // 通知本文をタップして AnswerView を開くとき
    var onOpenAnswer: ((UUID, UUID) -> Void)?

    // 友達申請の承認・拒否
    var onFriendRequestAccept:  ((String, String, String, String, String?) -> Void)?
    var onFriendRequestDecline: ((String) -> Void)?

    // 友達申請が承認されたとき（送信者側に届く通知）
    var onFriendRequestAccepted: (() -> Void)?

    // チャット通知タップ → 該当チャットを開く
    var onOpenChat: ((UUID) -> Void)?

    // 現在表示中のチャットの questionId（このチャットの通知は抑制する）
    var activeChatQuestionId: UUID?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func registerFriendRequestCategory() {
        let accept = UNNotificationAction(
            identifier: Self.friendRequestAcceptId,
            title: "○ 承認",
            options: []
        )
        let decline = UNNotificationAction(
            identifier: Self.friendRequestDeclineId,
            title: "✕ 断る",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.friendRequestCategoryId,
            actions: [accept, decline],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var updated = existing.filter { $0.identifier != Self.friendRequestCategoryId }
            updated.insert(category)
            UNUserNotificationCenter.current().setNotificationCategories(updated)
        }
    }

    func registerChatCategory() {
        let category = UNNotificationCategory(
            identifier: Self.chatCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var updated = existing.filter { $0.identifier != Self.chatCategoryId }
            updated.insert(category)
            UNUserNotificationCenter.current().setNotificationCategories(updated)
        }
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

    func scheduleAutoReminder(
        questionId:   UUID,
        memberId:     UUID,
        memberName:   String,
        memberEmoji:  String,
        questionText: String,
        choices:      [AnswerChoice] = [.yes, .no],
        afterSeconds: TimeInterval
    ) {
        let identifier = "kiku-reminder-\(questionId.uuidString)-\(memberId.uuidString)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: afterSeconds, repeats: false)

        let appGroup        = UserDefaults(suiteName: "group.com.yukichi.kiku")
        let senderName      = appGroup?.string(forKey: "kiku.profile.name")     ?? "きく"
        let senderEmoji     = appGroup?.string(forKey: "kiku.profile.emoji")    ?? "👤"

        let content = UNMutableNotificationContent()
        content.title              = "⏰ まだ回答がありません"
        content.body               = questionText
        content.sound              = .default
        content.categoryIdentifier = Self.categoryId(for: choices)
        content.interruptionLevel  = .active
        content.userInfo           = [
            "questionId":     questionId.uuidString,
            "memberId":       memberId.uuidString,
            "memberName":     memberName,
            "memberEmoji":    memberEmoji,
            "sentAt":         Date().timeIntervalSince1970,
            "senderName":     senderName,
            "senderEmoji":    senderEmoji,
            "senderIconMode": "emoji",
            "isReminder":     true
        ]

        let newCategory = UNNotificationCategory(
            identifier: Self.categoryId(for: choices),
            actions: choices.map { $0.makeNotificationAction() },
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var updated = existing.filter { $0.identifier != newCategory.identifier }
            updated.insert(newCategory)
            UNUserNotificationCenter.current().setNotificationCategories(updated)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func cancelAutoReminder(questionId: UUID, memberId: UUID) {
        let identifier = "kiku-reminder-\(questionId.uuidString)-\(memberId.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func scheduleQuestion(
        questionId:   UUID,
        memberId:     UUID,
        memberName:   String,
        memberEmoji:  String,
        questionText: String,
        choices:      [AnswerChoice] = [.yes, .no]
    ) {
        // 送信者プロフィールを App Group UserDefaults から読み込む
        let appGroup        = UserDefaults(suiteName: "group.com.yukichi.kiku")
        let senderName      = appGroup?.string(forKey: "kiku.profile.name")     ?? "きく"
        let senderEmoji     = appGroup?.string(forKey: "kiku.profile.emoji")    ?? "👤"
        let senderIconMode  = appGroup?.string(forKey: "kiku.profile.iconMode") ?? "emoji"
        let senderPhotoData = appGroup?.data(forKey: "kiku.profile.photo")

        let content = UNMutableNotificationContent()
        content.title               = "\(senderEmoji) \(senderName)さんから質問が届きました"
        content.body                = questionText
        content.sound               = .default
        content.categoryIdentifier  = Self.categoryId(for: choices)
        content.interruptionLevel   = .active
        content.userInfo            = [
            "questionId":     questionId.uuidString,
            "memberId":       memberId.uuidString,
            "memberName":     memberName,
            "memberEmoji":    memberEmoji,
            "sentAt":         Date().timeIntervalSince1970,
            "senderName":     senderName,
            "senderEmoji":    senderEmoji,
            "senderIconMode": senderIconMode
        ]

        let newCategory = UNNotificationCategory(
            identifier: Self.categoryId(for: choices),
            actions: choices.map { $0.makeNotificationAction() },
            intentIdentifiers: [],
            options: []
        )

        // カテゴリ登録が完了してから通知をスケジュールする（レース条件を回避）
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var updated = existing.filter { $0.identifier != newCategory.identifier }
            updated.insert(newCategory)
            UNUserNotificationCenter.current().setNotificationCategories(updated)

            let trigger    = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
            let identifier = "kiku-\(questionId.uuidString)-\(memberId.uuidString)"

            Task { @MainActor in
                let avatarImage = Self.makeSenderImage(
                    iconMode: senderIconMode,
                    emoji: senderEmoji,
                    photoData: senderPhotoData
                )
                guard let avatarImage, let avatarData = avatarImage.pngData() else {
                    try? await UNUserNotificationCenter.current().add(
                        UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    )
                    return
                }

                let handle = INPersonHandle(value: senderName, type: .unknown)
                let sender = INPerson(
                    personHandle: handle,
                    nameComponents: nil,
                    displayName: "\(senderEmoji) \(senderName)",
                    image: INImage(imageData: avatarData),
                    contactIdentifier: nil,
                    customIdentifier: nil
                )
                let intent = INSendMessageIntent(
                    recipients: nil,
                    outgoingMessageType: .outgoingMessageText,
                    content: questionText,
                    speakableGroupName: nil,
                    conversationIdentifier: senderName,
                    serviceName: "きく",
                    sender: sender,
                    attachments: nil
                )
                let interaction = INInteraction(intent: intent, response: nil)
                interaction.direction = .incoming
                try? await interaction.donate()

                let finalContent = (try? content.updating(from: intent)) ?? content
                try? await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: identifier, content: finalContent, trigger: trigger)
                )
            }
        }
    }

    func scheduleCompletion(question: Question) {
        let content = UNMutableNotificationContent()
        content.title = "全員揃いました 🎉"
        content.body = "「\(question.text)」に全員が回答しました"
        content.sound = .default
        content.interruptionLevel = .active
        let request = UNNotificationRequest(
            identifier: "completion.\(question.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 送信者アバター生成

    @MainActor
    private static func makeSenderImage(iconMode: String, emoji: String, photoData: Data?) -> UIImage? {
        if iconMode == "photo", let data = photoData, let image = UIImage(data: data) {
            return image
        }
        let size: CGFloat = 60
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size * 0.75)]
            let str = emoji as NSString
            let textSize = str.size(withAttributes: attrs)
            str.draw(
                at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2),
                withAttributes: attrs
            )
        }
    }

    // MARK: - 通知タップ処理

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier

        // チャットメッセージタップ → 該当チャットを開く
        if let type = userInfo["type"] as? String, type == "chatMessage",
           let qIdStr = userInfo["questionId"] as? String,
           let questionId = UUID(uuidString: qIdStr),
           actionId == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.onOpenChat?(questionId)
            }
            return
        }

        // 友達申請承認通知タップ
        if let type = userInfo["type"] as? String, type == "friendRequestAccepted",
           actionId == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.onFriendRequestAccepted?()
            }
            return
        }

        // 友達申請アクション
        if let type = userInfo["type"] as? String, type == "friendRequest",
           let requestId = userInfo["requestId"] as? String {
            let fromUID      = userInfo["fromUID"]      as? String ?? ""
            let fromName     = userInfo["fromName"]     as? String ?? ""
            let fromEmoji    = userInfo["fromEmoji"]    as? String ?? "👤"
            let rawPhotoURL  = userInfo["fromPhotoURL"] as? String
            let fromPhotoURL = rawPhotoURL?.isEmpty == false ? rawPhotoURL : nil
            switch actionId {
            case Self.friendRequestAcceptId:
                onFriendRequestAccept?(requestId, fromUID, fromName, fromEmoji, fromPhotoURL)
            case Self.friendRequestDeclineId:
                onFriendRequestDecline?(requestId)
            default:
                break
            }
            return
        }

        guard
            let qIdStr     = userInfo["questionId"] as? String,
            let mIdStr     = userInfo["memberId"]   as? String,
            let questionId = UUID(uuidString: qIdStr),
            let memberId   = UUID(uuidString: mIdStr)
        else { return }

        switch actionId {
        case AnswerChoice.yes.actionId:
            onAnswer?(questionId, memberId, "yes")

        case AnswerChoice.no.actionId:
            onAnswer?(questionId, memberId, "no")

        case AnswerChoice.time.actionId, AnswerChoice.freeText.actionId:
            if let textResponse = response as? UNTextInputNotificationResponse {
                let text = textResponse.userText.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    onAnswer?(questionId, memberId, text)
                }
            }

        case AnswerChoice.star.actionId:
            if let textResponse = response as? UNTextInputNotificationResponse {
                let text = textResponse.userText.trimmingCharacters(in: .whitespaces)
                if let n = Int(text), (1...5).contains(n) {
                    onAnswer?(questionId, memberId, "star:\(n)")
                }
            }

        case AnswerChoice.emoji.actionId:
            if let textResponse = response as? UNTextInputNotificationResponse {
                let text = textResponse.userText.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    onAnswer?(questionId, memberId, "emoji:\(text)")
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

    // アプリ起動中も通知をバナーで表示（チャット画面が開いている場合は抑制）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if let type = userInfo["type"] as? String, type == "chatMessage",
           let qIdStr = userInfo["questionId"] as? String,
           let questionId = UUID(uuidString: qIdStr),
           activeChatQuestionId == questionId {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound])
    }
}

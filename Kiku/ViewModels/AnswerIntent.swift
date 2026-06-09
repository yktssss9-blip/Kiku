import AppIntents
import ActivityKit

/// Live Activityのはい/いいえボタンで呼ばれるインテント
/// openAppWhenRun = true により iOS 全バージョンで確実に perform() が呼ばれる
struct AnswerIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "回答する"
    /// true: アプリを前面に開いて実行（iOS 18 の background実行バグを回避）
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Question ID") var questionId: String
    @Parameter(title: "Member ID")   var memberId: String
    @Parameter(title: "Value")       var value: String

    init() {}

    init(questionId: String, memberId: String, value: String) {
        self.questionId = questionId
        self.memberId   = memberId
        self.value      = value
    }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.yukichi.kiku")

        if value == "open_star" || value == "open_time" {
            // アプリを開いてピッカーを表示（答えはまだ保存しない）
            defaults?.set(value, forKey: "open_picker.\(questionId).\(memberId)")
            await MainActor.run {
                NotificationCenter.default.post(name: .kikuOpenPicker, object: nil)
            }
        } else {
            // yes/no/emoji 等は即座に保存
            defaults?.set(value, forKey: "answer.\(questionId).\(memberId)")
            await MainActor.run {
                NotificationCenter.default.post(name: .kikuAnswerSubmitted, object: nil)
            }
        }
        return .result()
    }
}

// MARK: - 友達申請 承認 / 辞退 Intent

struct FriendRequestResponseIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "友達申請に返答"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Request ID") var requestId: String
    @Parameter(title: "Accept")     var accept: Bool

    init() {}

    init(requestId: String, accept: Bool) {
        self.requestId = requestId
        self.accept    = accept
    }

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.com.yukichi.kiku")?
            .set(accept, forKey: "friendRequest.response.\(requestId)")
        await MainActor.run {
            NotificationCenter.default.post(name: .kikuFriendRequestResponse, object: nil)
        }
        return .result()
    }
}

extension Notification.Name {
    static let kikuAnswerSubmitted       = Notification.Name("kiku.answerSubmitted")
    static let kikuQuestionCompleted     = Notification.Name("kiku.questionCompleted")
    static let kikuOpenPicker            = Notification.Name("kiku.openPicker")
    static let kikuFriendRequestResponse = Notification.Name("kiku.friendRequestResponse")
    static let kikuOpenChat              = Notification.Name("kiku.openChat")
}

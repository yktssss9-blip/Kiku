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
        // App Groups 経由で回答を保存
        UserDefaults(suiteName: "group.com.yukichi.kiku")?
            .set(value, forKey: "answer.\(questionId).\(memberId)")

        // メインアプリのプロセス内で NotificationCenter を通じて即座に反映
        await MainActor.run {
            NotificationCenter.default.post(
                name: .kikuAnswerSubmitted,
                object: nil
            )
        }
        return .result()
    }
}

extension Notification.Name {
    static let kikuAnswerSubmitted   = Notification.Name("kiku.answerSubmitted")
    static let kikuQuestionCompleted = Notification.Name("kiku.questionCompleted")
}

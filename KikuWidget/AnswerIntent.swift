import AppIntents
import ActivityKit

/// ウィジェット Extension 側の stub
/// コンパイルのために定義が必要。実際の perform() は main app 側で実行される。
/// LiveActivityIntent 準拠により iOS がメインアプリ側へルーティングする。
struct AnswerIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "回答する"
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
        // stub: メインアプリ側の perform() が呼ばれるため、ここには到達しない想定
        return .result()
    }
}

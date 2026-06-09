import AppIntents
import ActivityKit

/// ウィジェット Extension 側の stub
/// コンパイルのために定義が必要。実際の perform() は main app 側で実行される。
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

    func perform() async throws -> some IntentResult { .result() }
}

/// 友達申請 承認/辞退 stub
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

    func perform() async throws -> some IntentResult { .result() }
}

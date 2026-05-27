import ActivityKit
import Foundation

public struct KikuActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var yesCount: Int
        public var noCount: Int
        public var pendingCount: Int

        public init(yesCount: Int, noCount: Int, pendingCount: Int) {
            self.yesCount = yesCount
            self.noCount = noCount
            self.pendingCount = pendingCount
        }
    }

    public var questionId: String
    public var questionText: String
    public var totalCount: Int
    public var memberId: String
    public var memberName: String
    public var sentAt: Date        // 質問を送った時刻（カウントアップ基点）

    public init(questionId: String, questionText: String, totalCount: Int, memberId: String, memberName: String, sentAt: Date) {
        self.questionId = questionId
        self.questionText = questionText
        self.totalCount = totalCount
        self.memberId = memberId
        self.memberName = memberName
        self.sentAt = sentAt
    }
}

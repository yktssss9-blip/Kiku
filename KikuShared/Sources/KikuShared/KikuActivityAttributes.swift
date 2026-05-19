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

    public init(questionId: String, questionText: String, totalCount: Int, memberId: String, memberName: String) {
        self.questionId = questionId
        self.questionText = questionText
        self.totalCount = totalCount
        self.memberId = memberId
        self.memberName = memberName
    }
}

import ActivityKit
import Foundation

// MARK: - 友達申請 Live Activity

public struct FriendRequestActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: String // "pending" | "accepted" | "declined"
        public init(status: String = "pending") { self.status = status }
    }

    public var requestId: String
    public var fromUID: String
    public var fromName: String
    public var fromEmoji: String
    public var sentAt: Date

    public init(requestId: String, fromUID: String, fromName: String, fromEmoji: String, sentAt: Date) {
        self.requestId = requestId
        self.fromUID   = fromUID
        self.fromName  = fromName
        self.fromEmoji = fromEmoji
        self.sentAt    = sentAt
    }
}

// MARK: - 質問 Live Activity

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
    public var sentAt: Date
    public var choices: [String]

    public init(questionId: String, questionText: String, totalCount: Int, memberId: String, memberName: String, sentAt: Date, choices: [String] = ["yes", "no"]) {
        self.questionId = questionId
        self.questionText = questionText
        self.totalCount = totalCount
        self.memberId = memberId
        self.memberName = memberName
        self.sentAt = sentAt
        self.choices = choices
    }
}

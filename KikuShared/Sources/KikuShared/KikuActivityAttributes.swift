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

    enum CodingKeys: String, CodingKey {
        case questionId, questionText, totalCount, memberId, memberName, sentAt, choices
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        questionId   = try c.decode(String.self, forKey: .questionId)
        questionText = try c.decode(String.self, forKey: .questionText)
        totalCount   = try c.decode(Int.self,    forKey: .totalCount)
        memberId     = try c.decode(String.self, forKey: .memberId)
        memberName   = try c.decode(String.self, forKey: .memberName)
        choices      = try c.decodeIfPresent([String].self, forKey: .choices) ?? ["yes", "no"]
        // push-to-start は Unix タイムスタンプ（秒）で送られるため Double → Date 変換
        if let ts = try? c.decode(Double.self, forKey: .sentAt) {
            sentAt = ts > 1_000_000_000 ? Date(timeIntervalSince1970: ts) : Date(timeIntervalSinceReferenceDate: ts)
        } else {
            sentAt = try c.decode(Date.self, forKey: .sentAt)
        }
    }
}

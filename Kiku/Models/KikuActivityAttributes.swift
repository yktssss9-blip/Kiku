import ActivityKit
import Foundation

struct KikuActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var yesCount: Int
        var noCount: Int
        var pendingCount: Int
    }

    var questionId: String
    var questionText: String
    var totalCount: Int
    var memberId: String
    var memberName: String
    var sentAt: Date        // 質問を送った時刻（カウントアップ基点）
}

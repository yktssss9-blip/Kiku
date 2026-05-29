import Foundation

// MARK: - 称号

struct PointTitle {
    let label: String
    let emoji: String
    let color: String   // SwiftUI Color名として使う

    var display: String { "\(emoji) \(label)" }

    /// rank: 1始まりの順位、outOf: 友達の総人数
    /// 10人未満は「支配者」「CEO」を解放せず7段階、10人以上で全9段階を開放
    init(rank: Int, outOf total: Int) {
        let fraction = total > 1 ? Double(rank - 1) / Double(total - 1) : 0.0

        let tier: Int
        if total >= 10 {
            // 全9段階（0=支配者 〜 8=新入社員）
            tier = min(Int(fraction * 9), 8)
        } else {
            // 上位2段階（支配者・CEO）は未解放 → 7段階（取締役〜新入社員）にマップ
            tier = min(Int(fraction * 7), 6) + 2
        }

        switch tier {
        case 0: label = "支配者";  emoji = "👑"; color = "purple"
        case 1: label = "CEO";   emoji = "👔"; color = "yellow"
        case 2: label = "取締役"; emoji = "🤵"; color = "orange"
        case 3: label = "部長";   emoji = "🏢"; color = "orange"
        case 4: label = "課長";   emoji = "🗂️"; color = "blue"
        case 5: label = "係長";   emoji = "📊"; color = "blue"
        case 6: label = "主任";   emoji = "📋"; color = "blue"
        case 7: label = "平社員"; emoji = "💼"; color = "gray"
        default: label = "新入社員"; emoji = "🐣"; color = "gray"
        }
    }
}

// MARK: - ポイント獲得ティア

enum PointTier: String, Codable {
    case fast         // 60秒以内  → +20pt ⚡️
    case normal       // 60〜180秒 → +10pt 🕐
    case late         // 180秒超   → +2pt  💬
    case senderFast   // 送信者: fast回答が来た → +5pt
    case senderNormal // 送信者: normal回答が来た → +2pt

    var points: Int {
        switch self {
        case .fast:         return 20
        case .normal:       return 10
        case .late:         return 2
        case .senderFast:   return 5
        case .senderNormal: return 2
        }
    }

    var label: String {
        switch self {
        case .fast:         return "⚡️ 超速"
        case .normal:       return "🕐 早い"
        case .late:         return "💬 普通"
        case .senderFast:   return "🎯 速答ボーナス"
        case .senderNormal: return "🎯 回答ボーナス"
        }
    }

    var pointLabel: String { "\(label) +\(points)pt" }

    static func tier(for elapsed: TimeInterval) -> PointTier {
        if elapsed < 60  { return .fast   }
        if elapsed < 180 { return .normal }
        return .late
    }
}

// MARK: - ポイント獲得記録

struct PointRecord: Identifiable, Codable {
    var id: UUID = UUID()
    var questionId:     UUID
    var memberId:       UUID
    var questionText:   String
    var tier:           PointTier
    var earnedAt:       Date = Date()
    var elapsedSeconds: Double?

    var points: Int { tier.points }

    init(id: UUID = UUID(), questionId: UUID, memberId: UUID,
         questionText: String, tier: PointTier, earnedAt: Date = Date(),
         elapsedSeconds: Double? = nil) {
        self.id = id; self.questionId = questionId; self.memberId = memberId
        self.questionText = questionText; self.tier = tier; self.earnedAt = earnedAt
        self.elapsedSeconds = elapsedSeconds
    }
}

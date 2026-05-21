import Foundation

// MARK: - ポイント獲得ティア

enum PointTier: String, Codable {
    case fast   // 60秒以内  → +20pt ⚡️
    case normal // 60〜180秒 → +10pt 🕐
    case late   // 180秒超   → +2pt  💬

    var points: Int {
        switch self {
        case .fast:   return 20
        case .normal: return 10
        case .late:   return 2
        }
    }

    var label: String {
        switch self {
        case .fast:   return "⚡️ 超速"
        case .normal: return "🕐 早い"
        case .late:   return "💬 普通"
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
    var questionId:   UUID
    var memberId:     UUID
    var questionText: String
    var tier:         PointTier
    var earnedAt:     Date = Date()

    var points: Int { tier.points }
}

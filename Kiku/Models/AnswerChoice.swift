import SwiftUI
import UserNotifications

// MARK: - AnswerChoice

enum AnswerChoice: String, Identifiable, CaseIterable, Codable {
    case yes
    case no
    case time
    case freeText

    var id: String { rawValue }

    // MARK: UI

    var icon: String {
        switch self {
        case .yes:      return "circle"
        case .no:       return "xmark"
        case .time:     return "clock"
        case .freeText: return "ellipsis"
        }
    }

    var tintColor: Color {
        switch self {
        case .yes:      return .green
        case .no:       return .red
        case .time:     return .blue
        case .freeText: return .purple
        }
    }

    var shortLabel: String? {
        switch self {
        case .yes, .no: return nil
        case .time:     return "時刻"
        case .freeText: return "自由記述"
        }
    }

    var menuLabel: String {
        switch self {
        case .yes:      return "○ はい"
        case .no:       return "✕ いいえ"
        case .time:     return "🕐 時刻を選ぶ"
        case .freeText: return "・・・ 自由に回答"
        }
    }

    // MARK: 通知アクション

    var actionId: String {
        switch self {
        case .yes:      return "ANSWER_YES"
        case .no:       return "ANSWER_NO"
        case .time:     return "ANSWER_TIME"
        case .freeText: return "ANSWER_FREETEXT"
        }
    }

    var actionTitle: String {
        switch self {
        case .yes:      return "✅ はい"
        case .no:       return "❌ いいえ"
        case .time:     return "🕐 時刻を入力"
        case .freeText: return "・・・ 自由に回答"
        }
    }

    func makeNotificationAction() -> UNNotificationAction {
        switch self {
        case .time:
            return UNTextInputNotificationAction(
                identifier: actionId,
                title: actionTitle,
                options: [],
                textInputButtonTitle: "送信",
                textInputPlaceholder: "例: 19:30"
            )
        case .freeText:
            return UNTextInputNotificationAction(
                identifier: actionId,
                title: actionTitle,
                options: [],
                textInputButtonTitle: "送信",
                textInputPlaceholder: "自由に入力"
            )
        default:
            return UNNotificationAction(
                identifier: actionId,
                title: actionTitle,
                options: []
            )
        }
    }
}

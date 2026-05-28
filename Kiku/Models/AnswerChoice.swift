import SwiftUI
import UserNotifications

// MARK: - AnswerChoice

enum AnswerChoice: String, Identifiable, CaseIterable, Codable {
    case yes
    case no
    case time
    case freeText
    case star
    case emoji

    var id: String { rawValue }

    // MARK: UI

    var icon: String {
        switch self {
        case .yes:      return "circle"
        case .no:       return "xmark"
        case .time:     return "clock"
        case .freeText: return "ellipsis"
        case .star:     return "star"
        case .emoji:    return "face.smiling"
        }
    }

    var tintColor: Color {
        switch self {
        case .yes:      return .green
        case .no:       return .red
        case .time:     return .blue
        case .freeText: return .purple
        case .star:     return .orange
        case .emoji:    return .yellow
        }
    }

    var shortLabel: String? {
        switch self {
        case .yes, .no: return nil
        case .time:     return "時刻"
        case .freeText: return "自由記述"
        case .star:     return "星評価"
        case .emoji:    return "絵文字"
        }
    }

    var menuLabel: String {
        switch self {
        case .yes:      return "○ はい"
        case .no:       return "✕ いいえ"
        case .time:     return "🕐 時刻を選ぶ"
        case .freeText: return "・・・ 自由に回答"
        case .star:     return "☆ 星で評価"
        case .emoji:    return "😊 絵文字で反応"
        }
    }

    // MARK: 通知アクション

    var actionId: String {
        switch self {
        case .yes:      return "ANSWER_YES"
        case .no:       return "ANSWER_NO"
        case .time:     return "ANSWER_TIME"
        case .freeText: return "ANSWER_FREETEXT"
        case .star:     return "ANSWER_STAR"
        case .emoji:    return "ANSWER_EMOJI"
        }
    }

    var actionTitle: String {
        switch self {
        case .yes:      return "✅ はい"
        case .no:       return "❌ いいえ"
        case .time:     return "🕐 時刻を入力"
        case .freeText: return "・・・ 自由に回答"
        case .star:     return "☆ 星で評価（1〜5）"
        case .emoji:    return "😊 絵文字で反応"
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
        case .star:
            return UNTextInputNotificationAction(
                identifier: actionId,
                title: actionTitle,
                options: [],
                textInputButtonTitle: "送信",
                textInputPlaceholder: "1〜5の数字を入力"
            )
        case .emoji:
            return UNTextInputNotificationAction(
                identifier: actionId,
                title: actionTitle,
                options: [],
                textInputButtonTitle: "送信",
                textInputPlaceholder: "絵文字を1つ入力"
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

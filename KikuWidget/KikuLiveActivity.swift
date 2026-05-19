import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - ロック画面通知バー

struct KikuLiveActivityView: View {
    let context: ActivityViewContext<KikuActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            // ヘッダー：アプリ名 + 経過タイマー
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.blue)
                Text("きく")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()

                // カウントアップタイマー
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(context.attributes.sentAt, style: .timer)
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(timerColor(from: context.attributes.sentAt))
                }
            }

            // 質問文
            Text(context.attributes.questionText)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            // 宛先 + ポイント案内
            HStack {
                Text("\(context.attributes.memberName)さんへ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                pointHint(from: context.attributes.sentAt)
            }

            // 集計バー
            HStack(spacing: 0) {
                summaryItem(label: "はい",   count: context.state.yesCount,     color: .green)
                Divider().frame(height: 24)
                summaryItem(label: "いいえ", count: context.state.noCount,      color: .secondary)
                Divider().frame(height: 24)
                summaryItem(label: "未回答", count: context.state.pendingCount, color: .orange)
            }
            .padding(.vertical, 4)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // はい / いいえ ボタン
            HStack(spacing: 10) {
                answerLink(label: "✅  はい",  value: "yes", bgColor: .green,                   fgColor: .white)
                answerLink(label: "❌  いいえ", value: "no",  bgColor: Color(UIColor.systemGray4), fgColor: .primary)
            }
        }
        .padding()
    }

    // 経過時間に応じてタイマーの色を変える
    private func timerColor(from date: Date) -> Color {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60  { return .green  }   // 1分以内（+20pt圏内）
        if elapsed < 180 { return .orange }   // 3分以内（+10pt圏内）
        return .red                            // 時間超過
    }

    // 残りポイント案内
    private func pointHint(from date: Date) -> some View {
        let elapsed = Date().timeIntervalSince(date)
        let text: String
        let color: Color
        if elapsed < 60 {
            text = "⚡️ 今なら +20pt"
            color = .green
        } else if elapsed < 180 {
            text = "🕐 今なら +10pt"
            color = .orange
        } else {
            text = "+2pt"
            color = .secondary
        }
        return Text(text).font(.caption2).foregroundStyle(color)
    }

    private func summaryItem(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)人").font(.title3).fontWeight(.bold).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func answerLink(label: String, value: String, bgColor: Color, fgColor: Color) -> some View {
        let url = URL(string: "kiku://answer?questionId=\(context.attributes.questionId)&memberId=\(context.attributes.memberId)&value=\(value)")!
        return Link(destination: url) {
            Text(label)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(fgColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(bgColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Widget設定

struct KikuLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KikuActivityAttributes.self) { context in
            KikuLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(.blue).font(.title3)
                        Text(context.attributes.memberName)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        // Dynamic Islandにもタイマー
                        Text(context.attributes.sentAt, style: .timer)
                            .font(.caption2).monospacedDigit()
                            .foregroundStyle(.orange)
                        Label("\(context.state.yesCount)", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.questionText)
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        let yesURL = URL(string: "kiku://answer?questionId=\(context.attributes.questionId)&memberId=\(context.attributes.memberId)&value=yes")!
                        let noURL  = URL(string: "kiku://answer?questionId=\(context.attributes.questionId)&memberId=\(context.attributes.memberId)&value=no")!
                        Link(destination: yesURL) {
                            Label("はい", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Link(destination: noURL) {
                            Label("いいえ", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color(UIColor.systemGray4))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "questionmark.circle.fill").foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.attributes.sentAt, style: .timer)
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.orange)
            } minimal: {
                Image(systemName: "questionmark.circle.fill").foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Preview

extension KikuActivityAttributes {
    static var preview: KikuActivityAttributes {
        KikuActivityAttributes(
            questionId:   "preview-q-id",
            questionText: "今夜ご飯食べる？",
            totalCount:   4,
            memberId:     "preview-m-id",
            memberName:   "お母さん",
            sentAt:       Date()
        )
    }
}

extension KikuActivityAttributes.ContentState {
    static var sample: KikuActivityAttributes.ContentState {
        KikuActivityAttributes.ContentState(yesCount: 2, noCount: 1, pendingCount: 1)
    }
}

#Preview("通知バー", as: .content, using: KikuActivityAttributes.preview) {
    KikuLiveActivityWidget()
} contentStates: {
    KikuActivityAttributes.ContentState.sample
}

#Preview("Dynamic Island 展開", as: .dynamicIsland(.expanded), using: KikuActivityAttributes.preview) {
    KikuLiveActivityWidget()
} contentStates: {
    KikuActivityAttributes.ContentState.sample
}

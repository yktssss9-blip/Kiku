import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - ロック画面

struct KikuLiveActivityView: View {
    let context: ActivityViewContext<KikuActivityAttributes>

    private var yesURL: URL {
        URL(string: "kiku://answer?questionId=\(context.attributes.questionId)&memberId=\(context.attributes.memberId)&value=yes")!
    }
    private var noURL: URL {
        URL(string: "kiku://answer?questionId=\(context.attributes.questionId)&memberId=\(context.attributes.memberId)&value=no")!
    }

    var body: some View {
        VStack(spacing: 10) {
            // 宛先 + タイマー + ポイントヒント
            HStack {
                Label("\(context.attributes.memberName)さんへ質問が届きました",
                      systemImage: "questionmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                Spacer()
                HStack(spacing: 4) {
                    Text(context.attributes.sentAt, style: .timer)
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(timerColor)
                    Text(pointLabel)
                        .font(.caption2).foregroundStyle(timerColor)
                }
            }

            // 質問文（大きく）
            Text(context.attributes.questionText)
                .font(.title3).fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity)

            // はい/いいえ ボタン（AppIntents：アプリを開かずに完結）
            HStack(spacing: 10) {
                Button(intent: AnswerIntent(
                    questionId: context.attributes.questionId,
                    memberId:   context.attributes.memberId,
                    value:      "yes"
                )) {
                    Label("はい", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button(intent: AnswerIntent(
                    questionId: context.attributes.questionId,
                    memberId:   context.attributes.memberId,
                    value:      "no"
                )) {
                    Label("いいえ", systemImage: "xmark.circle.fill")
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(UIColor.systemGray4))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var timerColor: Color {
        let e = Date().timeIntervalSince(context.attributes.sentAt)
        if e < 60  { return .green  }
        if e < 180 { return .orange }
        return .red
    }

    private var pointLabel: String {
        let e = Date().timeIntervalSince(context.attributes.sentAt)
        if e < 60  { return "⚡️+20pt" }
        if e < 180 { return "🕐+10pt"  }
        return "+2pt"
    }

    private func miniCount(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(count)").font(.caption).fontWeight(.bold).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
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
                    VStack(alignment: .leading, spacing: 1) {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(.blue).font(.title3)
                        Text(context.attributes.memberName)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.sentAt, style: .timer)
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.questionText)
                        .font(.caption).fontWeight(.semibold)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Button(intent: AnswerIntent(
                            questionId: context.attributes.questionId,
                            memberId:   context.attributes.memberId,
                            value:      "yes"
                        )) {
                            Label("はい", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(Color.green).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        Button(intent: AnswerIntent(
                            questionId: context.attributes.questionId,
                            memberId:   context.attributes.memberId,
                            value:      "no"
                        )) {
                            Label("いいえ", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(Color(UIColor.systemGray4)).foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: "questionmark.circle.fill").foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.attributes.sentAt, style: .timer)
                    .font(.caption2).monospacedDigit().foregroundStyle(.orange)
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

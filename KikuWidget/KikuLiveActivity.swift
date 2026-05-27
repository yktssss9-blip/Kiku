import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - ロック画面

struct KikuLiveActivityView: View {
    let context: ActivityViewContext<KikuActivityAttributes>

    var body: some View {
        VStack(spacing: 14) {

            // ── ヘッダー: 宛先 / タイマー / ポイントヒント ──
            HStack(alignment: .center) {
                // 宛先
                Label(context.attributes.memberName, systemImage: "person.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                // タイマー（中央寄り・大きく）
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.subheadline)
                        .foregroundStyle(timerColor)
                    Text(context.attributes.sentAt, style: .timer)
                        .font(.title3).fontWeight(.bold).monospacedDigit()
                        .foregroundStyle(timerColor)
                }

                Spacer()

                // ポイントヒント
                Text(pointLabel)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(timerColor)
            }

            // ── 質問文（大きく・中央） ──
            Text(context.attributes.questionText)
                .font(.title2).fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)

            // ── はい / いいえ ボタン ──
            HStack(spacing: 12) {
                Button(intent: AnswerIntent(
                    questionId: context.attributes.questionId,
                    memberId:   context.attributes.memberId,
                    value:      "yes"
                )) {
                    Label("はい", systemImage: "checkmark.circle.fill")
                        .font(.headline).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button(intent: AnswerIntent(
                    questionId: context.attributes.questionId,
                    memberId:   context.attributes.memberId,
                    value:      "no"
                )) {
                    Label("いいえ", systemImage: "xmark.circle.fill")
                        .font(.headline).fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(UIColor.systemGray4))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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

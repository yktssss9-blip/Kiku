import SwiftUI
import WidgetKit
import ActivityKit
import KikuShared

// MARK: - ロック画面

struct KikuLiveActivityView: View {
    let context: ActivityViewContext<KikuActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {

            // ── 上段: テキスト左 ＋ アプリアイコン右（BeReal 風） ──
            HStack(alignment: .top, spacing: 10) {

                VStack(alignment: .leading, spacing: 5) {
                    // 宛先
                    Text(context.attributes.memberName + "さんへ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    // 質問文（大きく）
                    Text(context.attributes.questionText)
                        .font(.title3).fontWeight(.bold)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // あとX人 バッジ
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text("あと\(context.state.pendingCount)人")
                            .font(.caption).fontWeight(.bold)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())

                    // 大きなタイマー ＋ ポイントヒント
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(context.attributes.sentAt, style: .timer)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(timerColor)

                        Text(pointLabel)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(timerColor)
                    }
                }

                Spacer(minLength: 4)

                // アプリアイコン（BeReal のカメラアイコンに相当）
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.blue)
                    .frame(width: 56)
                    .padding(.top, 2)
            }

            // ── 下段: はい / いいえ ボタン ──
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
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var timerColor: Color {
        let e = Date().timeIntervalSince(context.attributes.sentAt)
        if e < 60  { return .green  }
        if e < 180 { return .orange }
        return .red
    }

    private var pointLabel: String {
        let e = Date().timeIntervalSince(context.attributes.sentAt)
        if e < 60  { return "⚡️ 今なら +20pt" }
        if e < 180 { return "🕐 +10pt"  }
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
                HStack(spacing: 3) {
                    Text("\(context.state.pendingCount)")
                        .font(.caption2).fontWeight(.bold).foregroundStyle(.orange)
                    Text("人")
                        .font(.caption2).foregroundStyle(.secondary)
                }
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

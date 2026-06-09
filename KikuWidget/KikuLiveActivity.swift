import SwiftUI
import WidgetKit
import ActivityKit
import KikuShared

// MARK: - ロック画面

struct KikuLiveActivityView: View {
    let context: ActivityViewContext<KikuActivityAttributes>

    var body: some View {
        VStack(spacing: 8) {

            // ── 上段: テキスト左 ＋ アプリアイコン右（BeReal 風） ──
            HStack(alignment: .top, spacing: 10) {

                VStack(alignment: .leading, spacing: 3) {
                    // 宛先
                    Text(context.attributes.memberName + "さんへ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    // 質問文（大きく）
                    Text(context.attributes.questionText)
                        .font(.headline)
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
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())

                    // 大きなタイマー ＋ ポイントヒント
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(context.attributes.sentAt, style: .timer)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(timerColor)

                        Text(pointLabel)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(timerColor)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.blue)
                    .frame(width: 42)
                    .padding(.top, 2)
            }

            // ── 下段: 回答ボタン（choices によって切り替え） ──
            answerButtons(context: context)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    // MARK: - 回答ボタン群

    @ViewBuilder
    private func answerButtons(context: ActivityViewContext<KikuActivityAttributes>) -> some View {
        let ch = context.attributes.choices

        if ch.contains("emoji") {
            emojiButtonRow(context: context)
        } else if ch.contains("star") {
            openAppButton(
                context: context,
                value:  "open_star",
                label:  "星で評価する",
                icon:   "star.fill",
                color:  .orange
            )
        } else {
            yesNoTimeRow(context: context)
        }
    }

    // 絵文字5ボタン
    private func emojiButtonRow(context: ActivityViewContext<KikuActivityAttributes>) -> some View {
        HStack(spacing: 6) {
            ForEach(["😊", "😭", "🔥", "👍", "❤️"], id: \.self) { emoji in
                Button(intent: AnswerIntent(
                    questionId: context.attributes.questionId,
                    memberId:   context.attributes.memberId,
                    value:      "emoji:\(emoji)"
                )) {
                    Text(emoji)
                        .font(.system(size: 24))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color(UIColor.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // yes / no / time ボタン行
    private func yesNoTimeRow(context: ActivityViewContext<KikuActivityAttributes>) -> some View {
        let ch = context.attributes.choices
        return HStack(spacing: 10) {
            if ch.contains("yes") {
                Button(intent: AnswerIntent(
                    questionId: context.attributes.questionId,
                    memberId:   context.attributes.memberId,
                    value:      "yes"
                )) {
                    Label("はい", systemImage: "checkmark.circle.fill")
                        .font(.headline).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            if ch.contains("no") {
                Button(intent: AnswerIntent(
                    questionId: context.attributes.questionId,
                    memberId:   context.attributes.memberId,
                    value:      "no"
                )) {
                    Label("いいえ", systemImage: "xmark.circle.fill")
                        .font(.headline).fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color(UIColor.systemGray4))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            if ch.contains("time") {
                openAppButton(
                    context: context,
                    value:  "open_time",
                    label:  "時間を選ぶ",
                    icon:   "clock.fill",
                    color:  .blue
                )
            }
        }
    }

    // アプリを開くボタン（星・時間共用）
    private func openAppButton(
        context: ActivityViewContext<KikuActivityAttributes>,
        value: String,
        label: String,
        icon: String,
        color: Color
    ) -> some View {
        Button(intent: AnswerIntent(
            questionId: context.attributes.questionId,
            memberId:   context.attributes.memberId,
            value:      value
        )) {
            Label(label, systemImage: icon)
                .font(.headline).fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - タイマー色・ポイントラベル

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
                    dynamicIslandButtons(context: context)
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

    @ViewBuilder
    private func dynamicIslandButtons(context: ActivityViewContext<KikuActivityAttributes>) -> some View {
        let ch = context.attributes.choices

        if ch.contains("emoji") {
            HStack(spacing: 5) {
                ForEach(["😊", "😭", "🔥", "👍", "❤️"], id: \.self) { emoji in
                    Button(intent: AnswerIntent(
                        questionId: context.attributes.questionId,
                        memberId:   context.attributes.memberId,
                        value:      "emoji:\(emoji)"
                    )) {
                        Text(emoji)
                            .font(.system(size: 20))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(Color(UIColor.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if ch.contains("star") {
            Button(intent: AnswerIntent(
                questionId: context.attributes.questionId,
                memberId:   context.attributes.memberId,
                value:      "open_star"
            )) {
                Label("星で評価する", systemImage: "star.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(Color.orange).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                if ch.contains("yes") {
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
                }
                if ch.contains("no") {
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
                if ch.contains("time") {
                    Button(intent: AnswerIntent(
                        questionId: context.attributes.questionId,
                        memberId:   context.attributes.memberId,
                        value:      "open_time"
                    )) {
                        Label("時間", systemImage: "clock.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(Color.blue).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 友達申請 Live Activity

struct FriendRequestLiveActivityView: View {
    let context: ActivityViewContext<FriendRequestActivityAttributes>

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("友達申請が届きました")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(context.attributes.fromEmoji) \(context.attributes.fromName)")
                        .font(.headline)
                        .lineLimit(1)
                    Text("@\(context.attributes.fromEmoji)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
                    .frame(width: 42)
                    .padding(.top, 2)
            }

            HStack(spacing: 10) {
                // 承認: ○
                Button(intent: FriendRequestResponseIntent(requestId: context.attributes.requestId, accept: true)) {
                    Text("○")
                        .font(.title2).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                // 辞退: ✕
                Button(intent: FriendRequestResponseIntent(requestId: context.attributes.requestId, accept: false)) {
                    Text("✕")
                        .font(.title2).fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color(UIColor.systemGray4))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

struct FriendRequestLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FriendRequestActivityAttributes.self) { context in
            FriendRequestLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(.blue).font(.title3)
                        Text(context.attributes.fromName)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.sentAt, style: .timer)
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("友達申請が届きました")
                        .font(.caption).fontWeight(.semibold)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Button(intent: FriendRequestResponseIntent(requestId: context.attributes.requestId, accept: true)) {
                            Text("○ 承認")
                                .font(.headline).fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(Color.green)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        Button(intent: FriendRequestResponseIntent(requestId: context.attributes.requestId, accept: false)) {
                            Text("✕ 辞退")
                                .font(.headline).fontWeight(.bold)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(Color(UIColor.systemGray4))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: "person.badge.plus").foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.attributes.fromEmoji).font(.caption2)
            } minimal: {
                Image(systemName: "person.badge.plus").foregroundStyle(.blue)
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
            sentAt:       Date(),
            choices:      ["yes", "no"]
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

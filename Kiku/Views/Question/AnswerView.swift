import SwiftUI

struct AnswerView: View {
    let question: Question
    let memberId: UUID
    let memberName: String
    let memberEmoji: String
    var memberPhotoURL: String? = nil
    var isInvite: Bool = false
    var jumpToTimePicker: Bool = false

    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // MARK: - Step

    private enum Step { case initial, time, starComment }
    @State private var step: Step = .initial
    @State private var selectedYesNo: String = ""   // "yes" or "no"
    @State private var timeDate: Date = Date()
    @State private var answered: String? = nil
    @State private var hoveredStar: Int = 0
    @State private var selectedStar: Int = 0
    @State private var starCommentText: String = ""

    // MARK: - 回答変更（Pro限定・1質問につき1回）

    @State private var isEditing: Bool = false
    @State private var hasUsedEdit: Bool = false
    @State private var showPaywall: Bool = false

    // MARK: - Urgency Timer

    @State private var elapsed: TimeInterval = 0
    private let urgencyTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var currentTier: PointTier { PointTier.tier(for: elapsed) }

    private var answeredCount: Int {
        question.answers.filter { $0.value != "pending" }.count
    }

    private var myAnswer: Answer? {
        question.answers.first { $0.memberId == memberId }
    }

    private var canEditAnswer: Bool {
        guard let myAnswer, myAnswer.value != "pending" else { return false }
        return !myAnswer.hasBeenEdited && !hasUsedEdit
    }

    private var choices: [AnswerChoice] { question.answerChoices }
    private var hasYesNo: Bool { choices.contains(.yes) || choices.contains(.no) }
    private var hasTime:  Bool { choices.contains(.time) }
    private var hasStar:  Bool { choices.contains(.star) }
    private var hasEmoji: Bool { choices.contains(.emoji) }

    private static let emojiOptions = [
        "😊","😍","🥰","😂","😭","😡","😮","🤔",
        "👍","👎","🔥","❤️","💯","🎉","💪","🤯"
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.top, 48)
                    .padding(.horizontal, 24)
                Spacer()
                questionSection
                    .padding(.horizontal, 24)
                Spacer()
                if answered != nil {
                    confirmedSection
                        .padding(.bottom, 48)
                } else {
                    urgencyBanner
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)

                    if answeredCount > 0 {
                        alreadyAnsweredBadge
                            .padding(.bottom, 12)
                    }

                    switch step {
                    case .initial:
                        answersSection
                            .padding(.horizontal, 24)
                            .padding(.bottom, 48)
                    case .time:
                        timeSection
                            .padding(.horizontal, 24)
                            .padding(.bottom, 48)
                    case .starComment:
                        starCommentSection
                            .padding(.horizontal, 24)
                            .padding(.bottom, 48)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            elapsed = Date().timeIntervalSince(question.createdAt)
            if answered == nil, let myAnswer, myAnswer.value != "pending" {
                answered = myAnswer.value
            }
            if jumpToTimePicker && hasTime {
                step = .time
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(purchaseStore)
        }
        .onReceive(urgencyTimer) { _ in
            elapsed = Date().timeIntervalSince(question.createdAt)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("シゴでき")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    UserAvatarView(emoji: memberEmoji, photoURL: memberPhotoURL, size: 28)
                    Text("\(memberName)さんへの質問")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Question

    private var questionSection: some View {
        VStack(spacing: 20) {
            UserAvatarView(emoji: memberEmoji, photoURL: memberPhotoURL, size: 88)
            Text(question.text)
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - 全選択肢セクション

    @ViewBuilder
    private var answersSection: some View {
        VStack(spacing: 16) {
            if hasYesNo {
                yesNoRow
            }
            if !hasYesNo && hasTime {
                timeOnlyButton
            }
            if hasStar {
                starRow
            }
            if hasEmoji {
                emojiGrid
            }
        }
    }

    private var timeOnlyButton: some View {
        Button {
            withAnimation(.spring(response: 0.3)) { step = .time }
        } label: {
            primaryButtonLabel(icon: "clock.fill", text: "時刻を選ぶ", color: .blue)
        }
    }

    // MARK: - ○ / × 行

    private var yesNoRow: some View {
        HStack(spacing: 20) {
            if choices.contains(.yes) {
                Button { pressedYes() } label: {
                    VStack(spacing: 10) {
                        Text("○")
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(.green)
                        if hasTime {
                            subLabel(icon: "clock", text: "時刻を選ぶ", color: .green)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.green.opacity(0.35), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }

            if choices.contains(.no) {
                Button { pressedNo() } label: {
                    VStack(spacing: 10) {
                        Text("✕")
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(Color.red.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.red.opacity(0.28), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }

            Button { pressedRead() } label: {
                VStack(spacing: 10) {
                    Text("👀")
                        .font(.system(size: 40))
                    Text("既読")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .background(Color.gray.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 星評価行

    private var starRow: some View {
        VStack(spacing: 12) {
            Text("星で評価してください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        selectedStar = n
                        starCommentText = ""
                        withAnimation(.spring(response: 0.3)) { step = .starComment }
                    } label: {
                        Text(n <= hoveredStar ? "★" : "☆")
                            .font(.system(size: 52))
                            .foregroundStyle(n <= hoveredStar ? Color.orange : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        hoveredStar = inside ? n : 0
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in hoveredStar = n }
                            .onEnded   { _ in hoveredStar = 0 }
                    )
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 1.5)
            )
        }
    }

    // MARK: - 絵文字グリッド

    private var emojiGrid: some View {
        VStack(spacing: 12) {
            Text("絵文字で反応してください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 4),
                spacing: 8
            ) {
                ForEach(Self.emojiOptions, id: \.self) { emoji in
                    Button {
                        submitAnswer("emoji:\(emoji)")
                    } label: {
                        Text(emoji)
                            .font(.system(size: 36))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.yellow.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1.5)
            )
        }
    }

    private func subLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2)
        }
        .foregroundStyle(color.opacity(0.8))
    }

    // MARK: - Step 2a: 時刻ピッカー（○ の後）

    private var timeSection: some View {
        VStack(spacing: 16) {
            HStack {
                backButton { withAnimation(.spring(response: 0.3)) { step = .initial } }
                Spacer()
                selectedBadge
            }

            Text("時刻を選んでください")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            DatePicker("時刻", selection: $timeDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

            Button {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                submitAnswer(formatter.string(from: timeDate))
            } label: {
                primaryButtonLabel(
                    icon: "clock.fill",
                    text: "この時刻で回答",
                    color: .blue
                )
            }
        }
    }

    // MARK: - Step 2b: 星評価後コメント入力

    private var starCommentSection: some View {
        VStack(spacing: 16) {
            HStack {
                backButton {
                    withAnimation(.spring(response: 0.3)) {
                        step = .initial
                        hoveredStar = 0
                    }
                }
                Spacer()
                Text(String(repeating: "★", count: selectedStar) + String(repeating: "☆", count: 5 - selectedStar))
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
            }

            Text("コメントを書いてください（任意）")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("感想・コメントを入力", text: $starCommentText, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(Color(UIColor.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1.5)
                )

            Button {
                let trimmed = starCommentText.trimmingCharacters(in: .whitespaces)
                let value = trimmed.isEmpty ? "star:\(selectedStar)" : "star:\(selectedStar):\(trimmed)"
                submitAnswer(value)
            } label: {
                primaryButtonLabel(
                    icon: "paperplane.fill",
                    text: "この内容で送信",
                    color: .orange
                )
            }

            Button("コメントなしで送信") {
                submitAnswer("star:\(selectedStar)")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Confirmed

    private var confirmedSection: some View {
        VStack(spacing: 16) {
            confirmedIcon
                .transition(.scale.combined(with: .opacity))

            Text("「\(displayValue(answered ?? ""))」で回答しました")
                .font(.headline)
                .foregroundStyle(.secondary)

            if answered?.hasPrefix("star:") == true, let url = AppConstants.appStoreReviewURL {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                        Text("App Store でレビューを書く")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .clipShape(Capsule())
                }

                Text("アプリの感想をみんなに届けよう")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if canEditAnswer {
                editAnswerButton
            }

            Button("閉じる") { dismiss() }
                .font(.body)
                .foregroundStyle(.blue)
                .padding(.top, 4)
        }
    }

    private var editAnswerButton: some View {
        Button {
            if purchaseStore.isPro {
                withAnimation(.spring(response: 0.3)) {
                    isEditing       = true
                    answered        = nil
                    step            = .initial
                    selectedYesNo   = ""
                    selectedStar    = 0
                    starCommentText = ""
                }
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                Text("回答を変更する")
                if !purchaseStore.isPro {
                    Text("👑").font(.caption)
                }
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.blue)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var confirmedIcon: some View {
        let v = answered ?? ""
        if v == "yes" || v.hasPrefix("yes:") {
            Text("○")
                .font(.system(size: 80, weight: .bold))
                .foregroundStyle(.green)
        } else if v == "no" || v.hasPrefix("no:") {
            Text("✕")
                .font(.system(size: 80, weight: .bold))
                .foregroundStyle(.red)
        } else if v == "read" {
            VStack(spacing: 8) {
                Text("👀")
                    .font(.system(size: 64))
                Text("既読")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.gray)
            }
        } else if isTimeValue(v) {
            Image(systemName: "clock.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
        } else if v.hasPrefix("star:") {
            let parts = v.dropFirst(5).split(separator: ":", maxSplits: 1)
            let n = Int(parts.first ?? "") ?? 0
            VStack(spacing: 8) {
                Text(String(repeating: "★", count: n) + String(repeating: "☆", count: 5 - n))
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                if parts.count > 1 {
                    Text(String(parts[1]))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
        } else if v.hasPrefix("emoji:") {
            Text(String(v.dropFirst(6)))
                .font(.system(size: 80))
        } else {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 64))
                .foregroundStyle(.purple)
        }
    }

    // MARK: - Urgency Banner

    private var urgencyBanner: some View {
        let tier = currentTier
        let (icon, label, accent): (String, String, Color) = {
            switch tier {
            case .fast:   return ("⚡️", "超速！",  .orange)
            case .normal: return ("🕐", "早い回答", .blue)
            default:      return ("💬", "普通",     Color(UIColor.systemGray))
            }
        }()

        let remaining: TimeInterval? = {
            switch tier {
            case .fast:   return max(0, 60  - elapsed)
            case .normal: return max(0, 180 - elapsed)
            default:      return nil
            }
        }()

        let progress: Double = {
            switch tier {
            case .fast:   return min(elapsed / 60,            1.0)
            case .normal: return min((elapsed - 60) / 120,   1.0)
            default:      return 1.0
            }
        }()

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(icon).font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(accent)
                    if let rem = remaining {
                        Text("残り\(Int(rem))秒")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(accent.opacity(0.8))
                            .monospacedDigit()
                    }
                }

                Spacer()

                if let rem = remaining {
                    ZStack {
                        Circle()
                            .stroke(accent.opacity(0.2), lineWidth: 3)
                            .frame(width: 40, height: 40)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.9), value: progress)
                        Text("\(Int(rem))")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(accent)
                            .monospacedDigit()
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(accent.opacity(0.15))
                        .frame(height: 6)
                    Capsule()
                        .fill(accent)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.linear(duration: 0.9), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.25), lineWidth: 1.5)
        )
    }

    // MARK: - Already Answered Badge

    private var alreadyAnsweredBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("すでに \(answeredCount) 人が回答済み")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(Capsule())
    }

    // MARK: - Shared UI Parts

    private var selectedBadge: some View {
        let isYes = selectedYesNo == "yes"
        return Text(isYes ? "○ で回答中" : "✕ で回答中")
            .font(.caption).fontWeight(.semibold)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(isYes ? Color.green.opacity(0.12) : Color.red.opacity(0.10))
            .foregroundStyle(isYes ? .green : .red)
            .clipShape(Capsule())
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("戻る")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func primaryButtonLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.title3)
            Text(text).font(.body).fontWeight(.bold)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity).frame(height: 56)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func displayValue(_ value: String) -> String {
        switch value {
        case "yes":  return "○"
        case "no":   return "✕"
        case "read": return "既読"
        default:
            if value.hasPrefix("yes:")   { return "○ \(value.dropFirst(4))" }
            if value.hasPrefix("no:")    { return "✕ \(value.dropFirst(3))" }
            if value.hasPrefix("star:")  {
                let parts = value.dropFirst(5).split(separator: ":", maxSplits: 1)
                let n = Int(parts.first ?? "") ?? 0
                let stars = String(repeating: "★", count: n) + String(repeating: "☆", count: 5 - n)
                if parts.count > 1 { return "\(stars) \(parts[1])" }
                return stars
            }
            if value.hasPrefix("emoji:") { return String(value.dropFirst(6)) }
            return value
        }
    }

    // MARK: - Actions

    private func pressedYes() {
        selectedYesNo = "yes"
        if hasTime {
            withAnimation(.spring(response: 0.3)) { step = .time }
        } else {
            submitAnswer("yes")
        }
    }

    private func pressedNo() {
        submitAnswer("no")
    }

    private func pressedRead() {
        submitAnswer("read")
    }

    private func submitAnswer(_ value: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            answered = value
        }
        if isEditing {
            questionStore.editAnswer(questionId: question.id, memberId: memberId, newValue: value)
            isEditing    = false
            hasUsedEdit  = true
            Task {
                if !value.hasPrefix("star:") {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run { dismiss() }
                }
            }
            return
        }
        if isInvite {
            questionStore.submitInviteAnswer(questionId: question.id, memberId: memberId, value: value)
            Task {
                if !value.hasPrefix("star:") {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run { dismiss() }
                }
            }
        } else {
            if questionStore.questions.contains(where: { $0.id == question.id }) {
                questionStore.submit(questionId: question.id, memberId: memberId, value: value)
            } else {
                questionStore.submitReceived(questionId: question.id, memberId: memberId, value: value)
            }
            Task {
                await ActivityManager.shared.end(questionId: question.id, memberId: memberId)
                // 星回答はボタン操作待ちのため自動クローズしない
                if !value.hasPrefix("star:") {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run { dismiss() }
                }
            }
        }
    }
}

#Preview {
    let q = Question(
        text:    "今夜ご飯食べる？",
        groupId: UUID(),
        answers: [Answer(memberId: UUID(), value: "pending")],
        choices: ["yes", "no", "time", "freeText"]
    )
    AnswerView(
        question:    q,
        memberId:    q.answers[0].memberId,
        memberName:  "お母さん",
        memberEmoji: "👩"
    )
    .environmentObject(QuestionStore())
}

import SwiftUI
import UserNotifications

// MARK: - Data Model

struct NotifItem: Identifiable {
    var id: String          // UNNotification request identifier
    var questionId: UUID
    var memberId: UUID
    var questionText: String
    var memberName: String
    var memberEmoji: String
    var sentAt: Date        // 質問が作成された時刻
    var answerChoices: [AnswerChoice]
}

// MARK: - NotificationInboxView

struct NotificationInboxView: View {
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var profileStore:  ProfileStore

    /// 自分（myId）宛の未回答通知のみ表示
    private var pendingItems: [NotifItem] {
        let myId = profileStore.myId
        var items: [NotifItem] = []
        for question in questionStore.questions {
            for answer in question.answers
                where answer.value == "pending" && answer.memberId == myId {
                items.append(NotifItem(
                    id:            "\(question.id)-\(answer.memberId)",
                    questionId:    question.id,
                    memberId:      answer.memberId,
                    questionText:  question.text,
                    memberName:    "",
                    memberEmoji:   "",
                    sentAt:        question.createdAt,
                    answerChoices: question.answerChoices
                ))
            }
        }
        return items.sorted { $0.sentAt > $1.sentAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if pendingItems.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(pendingItems) { item in
                                PendingNotifCard(item: item) { value in
                                    answer(item, value: value)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("未回答の通知はありません")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Answer

    private func answer(_ item: NotifItem, value: String) {
        questionStore.submit(questionId: item.questionId, memberId: item.memberId, value: value)
        // iOS 通知センターからも削除（残っていれば）
        let notifId = "kiku-\(item.questionId.uuidString)-\(item.memberId.uuidString)"
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [notifId])
    }
}

// MARK: - PendingNotifCard

struct PendingNotifCard: View {
    let item: NotifItem
    let onAnswer: (String) -> Void

    @State private var elapsed: TimeInterval = 0
    @State private var showTimePicker  = false
    @State private var showFreeText    = false
    @State private var showStarPicker  = false
    @State private var showEmojiPicker = false
    @State private var showReportSheet = false
    @State private var timeDate        = Date()
    @State private var freeTextInput   = ""

    private static let emojiOptions = [
        "😊","😍","🥰","😂","😭","😡","😮","🤔",
        "👍","👎","🔥","❤️","💯","🎉","💪","🤯"
    ]

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── ヘッダー：メンバー名 + タイマー ──
            HStack(spacing: 8) {
                Text(item.memberEmoji)
                    .font(.title3)
                Text("\(item.memberName)さんへ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                timerBadge
            }

            // ── 質問文 ──
            Text(item.questionText)
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .contextMenu {
                    Button(role: .destructive) {
                        showReportSheet = true
                    } label: {
                        Label("通報する", systemImage: "exclamationmark.bubble")
                    }
                }

            // ── 回答ボタン（answerChoices から動的生成） ──
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(item.answerChoices) { choice in
                    choiceButton(choice)
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .onAppear {
            elapsed = max(0, -item.sentAt.timeIntervalSinceNow)
        }
        .onReceive(ticker) { _ in
            elapsed = max(0, -item.sentAt.timeIntervalSinceNow)
        }
        // ── 時刻ピッカーシート ──
        .sheet(isPresented: $showTimePicker) {
            NavigationStack {
                VStack(spacing: 20) {
                    Text(item.questionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    DatePicker("時刻", selection: $timeDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                .padding(.top, 8)
                .navigationTitle("時刻で回答")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { showTimePicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("回答する") {
                            let fmt = DateFormatter()
                            fmt.dateFormat = "HH:mm"
                            onAnswer(fmt.string(from: timeDate))
                            showTimePicker = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        // ── 自由記述シート ──
        .sheet(isPresented: $showFreeText) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.questionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("自由に入力してください", text: $freeTextInput, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
                .padding()
                .navigationTitle("自由記述で回答")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            freeTextInput = ""
                            showFreeText = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("送信") {
                            let text = freeTextInput.trimmingCharacters(in: .whitespaces)
                            onAnswer("yes:\(text)")
                            freeTextInput = ""
                            showFreeText = false
                        }
                        .fontWeight(.semibold)
                        .disabled(freeTextInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        // ── 星評価シート ──
        .sheet(isPresented: $showStarPicker) {
            NavigationStack {
                VStack(spacing: 24) {
                    Text(item.questionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack(spacing: 16) {
                        ForEach(1...5, id: \.self) { n in
                            Button {
                                onAnswer("star:\(n)")
                                showStarPicker = false
                            } label: {
                                Text("★")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 12)

                    Text("タップした星の数で評価されます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                .navigationTitle("星で評価")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { showStarPicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        // ── 絵文字ピッカーシート ──
        .sheet(isPresented: $showEmojiPicker) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text(item.questionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 4),
                        spacing: 12
                    ) {
                        ForEach(Self.emojiOptions, id: \.self) { emoji in
                            Button {
                                onAnswer("emoji:\(emoji)")
                                showEmojiPicker = false
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 40))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 64)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 8)
                .navigationTitle("絵文字で反応")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { showEmojiPicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheet(
                contentType: "question",
                contentId: item.questionId.uuidString,
                contentText: item.questionText
            )
        }
    }

    // MARK: - Timer Badge

    private var tierInfo: (icon: String, label: String, color: Color) {
        switch elapsed {
        case ..<60:   return ("⚡️", "超速",  .green)
        case ..<180:  return ("🕐", "早い",  .orange)
        default:      return ("💬", "普通",  .secondary)
        }
    }

    private var timerBadge: some View {
        let t = tierInfo
        return HStack(spacing: 4) {
            Text(t.icon).font(.caption)
            Text(elapsedString).font(.caption).monospacedDigit()
            Text(t.label).font(.caption2).foregroundStyle(t.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(t.color.opacity(0.1))
        .clipShape(Capsule())
    }

    private var elapsedString: String {
        let s = Int(elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Choice Button

    @ViewBuilder
    private func choiceButton(_ choice: AnswerChoice) -> some View {
        Button {
            switch choice {
            case .yes:      onAnswer("yes")
            case .no:       onAnswer("no")
            case .time:     showTimePicker  = true
            case .freeText: showFreeText    = true
            case .star:     showStarPicker  = true
            case .emoji:    showEmojiPicker = true
            }
        } label: {
            HStack(spacing: 6) {
                switch choice {
                case .yes:
                    Text("○").font(.title2).fontWeight(.bold)
                case .no:
                    Text("✕").font(.title2).fontWeight(.bold)
                case .time:
                    Image(systemName: "clock.fill").font(.body)
                    Text("時刻").font(.body).fontWeight(.semibold)
                case .freeText:
                    Text("・・・").font(.body).fontWeight(.bold)
                case .star:
                    Text("☆").font(.title2).fontWeight(.bold)
                    Text("星評価").font(.body).fontWeight(.semibold)
                case .emoji:
                    Text("😊").font(.title2)
                    Text("絵文字").font(.body).fontWeight(.semibold)
                }
            }
            .foregroundStyle(choice.tintColor)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(choice.tintColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(choice.tintColor.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

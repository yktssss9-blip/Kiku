import SwiftUI
import EventKit
import FirebaseAuth

struct ChatView: View {
    let session: ChatSession

    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var answerFilter: AnswerFilter = .all
    @State private var inputText = ""
    @FocusState private var isFocused: Bool

    @State private var shareItem: ShareItem? = nil
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var eventStore = EKEventStore()

    private let reactionEmojis = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    enum AnswerFilter: String, CaseIterable {
        case all   = "全員"
        case yes   = "はい"
        case no    = "いいえ"
    }

    private var currentSession: ChatSession? {
        chatStore.session(for: session.questionId)
    }

    private var filteredMessages: [ChatMessage] {
        guard let s = currentSession else { return [] }
        let channel: ChatChannel
        switch answerFilter {
        case .all: channel = .all
        case .yes: channel = .yes
        case .no:  channel = .no
        }
        return s.messages.filter { $0.channel == channel }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterTab
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredMessages) { message in
                            MessageBubble(message: message, myEmoji: profileStore.emoji, sessionId: session.id)
                                .contextMenu {
                                    messageContextMenu(for: message)
                                }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .onChange(of: filteredMessages.count) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onAppear {
                    proxy.scrollTo("bottom")
                }
            }
            Divider()
            inputBar
        }
        .navigationTitle(session.questionText)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            chatStore.markAsRead(sessionId: session.id)
            NotificationManager.shared.activeChatQuestionId = session.questionId
        }
        .onDisappear {
            if NotificationManager.shared.activeChatQuestionId == session.questionId {
                NotificationManager.shared.activeChatQuestionId = nil
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.value])
        }
        .alert("", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - コンテキストメニュー

    @ViewBuilder
    private func messageContextMenu(for message: ChatMessage) -> some View {
        ForEach(reactionEmojis, id: \.self) { emoji in
            Button {
                chatStore.toggleReaction(emoji: emoji, messageId: message.id, sessionId: session.id, senderId: profileStore.myId)
            } label: {
                Text(emoji)
            }
        }

        Divider()

        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("コピー", systemImage: "doc.on.doc")
        }

        Button {
            addToCalendar(message: message)
        } label: {
            Label("カレンダーに追加", systemImage: "calendar.badge.plus")
        }

        Button {
            addToReminders(message: message)
        } label: {
            Label("リマインダーに追加", systemImage: "checkmark.circle.badge.plus")
        }

        Button {
            shareItem = ShareItem(value: message.text)
        } label: {
            Label("共有", systemImage: "square.and.arrow.up")
        }

        if message.isFromMe {
            Divider()
            Button(role: .destructive) {
                chatStore.deleteMessage(messageId: message.id, sessionId: session.id)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    // MARK: - カレンダー追加

    private func addToCalendar(message: ChatMessage) {
        eventStore.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                guard granted else {
                    alertMessage = "カレンダーへのアクセスが許可されていません。設定アプリから許可してください。"
                    showAlert = true
                    return
                }
                let event = EKEvent(eventStore: eventStore)
                event.title = session.questionText
                event.notes = message.text
                event.startDate = Date()
                event.endDate = Date().addingTimeInterval(3600)
                event.calendar = eventStore.defaultCalendarForNewEvents
                do {
                    try eventStore.save(event, span: .thisEvent)
                    alertMessage = "カレンダーに追加しました"
                } catch {
                    alertMessage = "カレンダーへの追加に失敗しました"
                }
                showAlert = true
            }
        }
    }

    // MARK: - リマインダー追加

    private func addToReminders(message: ChatMessage) {
        eventStore.requestFullAccessToReminders { granted, _ in
            DispatchQueue.main.async {
                guard granted else {
                    alertMessage = "リマインダーへのアクセスが許可されていません。設定アプリから許可してください。"
                    showAlert = true
                    return
                }
                let reminder = EKReminder(eventStore: eventStore)
                reminder.title = message.text
                reminder.notes = session.questionText
                reminder.calendar = eventStore.defaultCalendarForNewReminders()
                do {
                    try eventStore.save(reminder, commit: true)
                    alertMessage = "リマインダーに追加しました"
                } catch {
                    alertMessage = "リマインダーへの追加に失敗しました"
                }
                showAlert = true
            }
        }
    }

    // MARK: - フィルタタブ

    private var filterTab: some View {
        HStack(spacing: 0) {
            ForEach(AnswerFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        answerFilter = filter
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(filterLabel(filter))
                            .font(.subheadline)
                            .fontWeight(answerFilter == filter ? .semibold : .regular)
                            .foregroundStyle(answerFilter == filter ? .primary : .secondary)
                        Rectangle()
                            .fill(answerFilter == filter ? Color.blue : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private func filterLabel(_ filter: AnswerFilter) -> String {
        guard let s = currentSession else { return filter.rawValue }
        switch filter {
        case .all:
            return "全員 \(s.memberAnswers.count)"
        case .yes:
            return "✅ はい \(s.yesMembers.count)"
        case .no:
            return "❌ いいえ \(s.noMembers.count)"
        }
    }

    // MARK: - 入力バー

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("メッセージを入力", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isFocused)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? Color.secondary : Color.blue
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let channel: ChatChannel
        switch answerFilter {
        case .all: channel = .all
        case .yes: channel = .yes
        case .no:  channel = .no
        }
        chatStore.send(
            text:              trimmed,
            isFromMe:          true,
            senderName:        profileStore.name,
            senderEmoji:       profileStore.emoji,
            channel:           channel,
            senderFirebaseUID: Auth.auth().currentUser?.uid,
            to:                session.id
        )
        inputText = ""
    }
}

// MARK: - ShareItem（sheet(item:) 用ラッパー）

struct ShareItem: Identifiable {
    let id = UUID()
    let value: String
}

// MARK: - ShareSheet（UIKit ラッパー）

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: ChatMessage
    let myEmoji: String
    let sessionId: UUID

    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var friendStore: FriendStore

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
            if message.isFromMe {
                myBubble
            } else {
                theirBubble
            }
            if !message.reactions.isEmpty {
                reactionBadgeRow
            }
        }
    }

    private var reactionBadgeRow: some View {
        HStack(spacing: 6) {
            ForEach(message.reactions.keys.sorted(), id: \.self) { emoji in
                let senders = message.reactions[emoji] ?? []
                let isMine  = senders.contains(profileStore.myId.uuidString)
                Button {
                    chatStore.toggleReaction(emoji: emoji, messageId: message.id, sessionId: sessionId, senderId: profileStore.myId)
                } label: {
                    HStack(spacing: 3) {
                        Text(emoji).font(.caption)
                        Text("\(senders.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isMine ? Color.blue.opacity(0.15) : Color(UIColor.secondarySystemBackground))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, message.isFromMe ? 38 : 40)
    }

    private var myBubble: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 60)
            timeLabel
            Text(message.text)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            UserAvatarView(emoji: profileStore.emoji, photoURL: profileStore.photoURL, size: 32)
        }
    }

    private var theirBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            let senderPhotoURL = message.senderFirebaseUID.flatMap { uid in
                friendStore.friends.first { $0.firebaseUID == uid }?.photoURL
            }
            UserAvatarView(emoji: message.senderEmoji.isEmpty ? "👤" : message.senderEmoji,
                           photoURL: senderPhotoURL,
                           size: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(message.senderName.isEmpty ? "メンバー" : message.senderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .bottom, spacing: 6) {
                    Text(message.text)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    timeLabel
                    Spacer(minLength: 60)
                }
            }
        }
    }

    private var timeLabel: some View {
        Text(message.sentAt.formatted(.dateTime.hour().minute()))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

import SwiftUI

struct ChatView: View {
    let session: ChatSession

    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var answerFilter: AnswerFilter = .all
    @State private var inputText = ""
    @FocusState private var isFocused: Bool

    enum AnswerFilter: String, CaseIterable {
        case all   = "全員"
        case yes   = "はい"
        case no    = "いいえ"
    }

    // 表示するセッション（最新状態を参照）
    private var currentSession: ChatSession? {
        chatStore.sessions.first { $0.id == session.id }
    }

    // フィルタ適用済みメッセージ
    private var filteredMessages: [ChatMessage] {
        guard let s = currentSession else { return [] }
        switch answerFilter {
        case .all:
            return s.messages
        case .yes:
            return s.messages.filter { $0.isFromMe || answerIsYes($0.answerValue) }
        case .no:
            return s.messages.filter { $0.isFromMe || answerIsNo($0.answerValue) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // はい/いいえ フィルタタブ
            filterTab

            Divider()

            // メッセージ一覧
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredMessages) { message in
                            MessageBubble(message: message, myEmoji: profileStore.emoji)
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

            // 入力欄
            inputBar
        }
        .navigationTitle(session.questionText)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            chatStore.markAsRead(sessionId: session.id)
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
        chatStore.send(
            text:        trimmed,
            isFromMe:    true,
            senderName:  profileStore.name,
            senderEmoji: profileStore.emoji,
            to:          session.id
        )
        inputText = ""
    }
}

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: ChatMessage
    let myEmoji: String

    var body: some View {
        if message.isFromMe {
            myBubble
        } else {
            theirBubble
        }
    }

    // 自分のメッセージ（右寄せ）
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
            Text(myEmoji)
                .font(.title3)
                .frame(width: 32, height: 32)
        }
    }

    // 相手のメッセージ（左寄せ）
    private var theirBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            // アバター
            Text(message.senderEmoji.isEmpty ? "👤" : message.senderEmoji)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                // 送信者名
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

import SwiftUI

struct ChatView: View {
    let session: ChatSession
    let friend: Friend?

    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var profileStore: ProfileStore
    @State private var inputText = ""
    @FocusState private var isFocused: Bool

    var messages: [ChatMessage] {
        chatStore.sessions.first { $0.id == session.id }?.messages ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // 開放のきっかけ
            unlockBanner
                .padding(.horizontal)
                .padding(.top, 8)

            // メッセージ一覧
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            MessageBubble(
                                message:    message,
                                myEmoji:    profileStore.emoji,
                                myName:     profileStore.name,
                                theirEmoji: friend?.emoji ?? "👤",
                                theirName:  friend?.name  ?? "メンバー"
                            )
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .onChange(of: messages.count) { _ in
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
        .navigationTitle(friend?.name ?? "チャット")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var unlockBanner: some View {
        let currentSession = chatStore.sessions.first { $0.id == session.id }
        let answerEmoji: String = {
            switch currentSession?.answerValue {
            case "yes": return "✅ はい"
            case "no":  return "❌ いいえ"
            default:    return ""
            }
        }()
        let bannerText: String = answerEmoji.isEmpty
            ? "「\(session.questionText)」への回答でチャットが開放されました"
            : "「\(session.questionText)」に \(answerEmoji) と回答してチャットが開放されました"

        return HStack(spacing: 6) {
            Image(systemName: "lock.open.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text(bannerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

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
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? Color.secondary : Color.blue)
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
        chatStore.send(text: trimmed, isFromMe: true, to: session.id)
        inputText = ""
    }
}

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: ChatMessage
    let myEmoji: String
    let myName: String
    let theirEmoji: String
    let theirName: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isFromMe {
                Spacer(minLength: 60)
                timeLabel
                bubble
                    .background(Color.blue)
                    .foregroundStyle(.white)
                avatar(emoji: myEmoji)
            } else {
                avatar(emoji: theirEmoji)
                bubble
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundStyle(.primary)
                timeLabel
                Spacer(minLength: 60)
            }
        }
    }

    private var bubble: some View {
        Text(message.text)
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var timeLabel: some View {
        Text(message.sentAt.formatted(.dateTime.hour().minute()))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func avatar(emoji: String) -> some View {
        Text(emoji)
            .font(.title3)
            .frame(width: 32, height: 32)
    }
}

import SwiftUI

struct ChatListView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var sessionToDelete: ChatSession? = nil
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if chatStore.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("チャット")
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("チャットがありません")
                .font(.headline)
            Text("質問に回答するとチャットが開放されます")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }

    // MARK: - List

    private var sessionList: some View {
        List {
            ForEach(chatStore.sessions.sorted { $0.lastMessageAt > $1.lastMessageAt }) { session in
                NavigationLink(destination: ChatView(session: session)) {
                    sessionRow(session: session)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        sessionToDelete = session
                        showDeleteAlert = true
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .alert("チャットを削除しますか？", isPresented: $showDeleteAlert, presenting: sessionToDelete) { s in
            Button("削除", role: .destructive) {
                chatStore.deleteSession(id: s.id)
                sessionToDelete = nil
            }
            Button("キャンセル", role: .cancel) {
                sessionToDelete = nil
            }
        } message: { s in
            Text("「\(s.questionText)」のチャット履歴をすべて削除します。この操作は元に戻せません。")
        }
    }

    private func sessionRow(session: ChatSession) -> some View {
        HStack(spacing: 12) {
            // 質問送信者（自分）のアバター
            creatorAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text(session.questionText)
                    .font(.headline)
                    .lineLimit(1)

                if let last = session.messages.last {
                    HStack(spacing: 4) {
                        if !last.isFromMe {
                            Text(last.senderName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(last.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("チャットが開放されました")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Spacer(minLength: 0)

            if let last = session.messages.last {
                Text(last.sentAt.formatted(.dateTime.hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    // 質問送信者（自分）のアバター
    @ViewBuilder
    private var creatorAvatar: some View {
        if let data = profileStore.photoData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        } else {
            Text(profileStore.emoji.isEmpty ? "👤" : profileStore.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(Circle())
        }
    }
}

#Preview {
    ChatListView()
        .environmentObject(ChatStore())
        .environmentObject(FriendStore())
        .environmentObject(ProfileStore())
}

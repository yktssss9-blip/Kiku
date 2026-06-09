import SwiftUI

struct ChatListView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var path: [ChatSession] = []
    @State private var sessionToDelete: ChatSession? = nil
    @State private var showDeleteAlert = false
    @State private var searchText: String = ""

    private var allSessions: [ChatSession] {
        chatStore.sessions + chatStore.receivedSessions
    }

    private var filteredSessions: [ChatSession] {
        let sorted = allSessions.sorted { $0.lastMessageAt > $1.lastMessageAt }
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.questionText.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if allSessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "質問を検索")
            .navigationTitle("チャット")
            .navigationDestination(for: ChatSession.self) { session in
                ChatView(session: session)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kikuOpenChat)) { notification in
            guard let questionId = notification.userInfo?["questionId"] as? UUID,
                  let session = allSessions.first(where: { $0.questionId == questionId })
            else { return }
            path = [session]
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
            if !searchText.isEmpty && filteredSessions.isEmpty {
                ContentUnavailableView(
                    "「\(searchText)」は見つかりません",
                    systemImage: "magnifyingglass"
                )
                .listRowSeparator(.hidden)
            }
            ForEach(filteredSessions) { session in
                NavigationLink(value: session) {
                    sessionRow(session: session)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if chatStore.isOwn(session) {
                        Button(role: .destructive) {
                            sessionToDelete = session
                            showDeleteAlert = true
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
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
            // 質問送信者のアバター（自分が作成した質問なら自分、受信した質問なら相手）
            avatar(for: session)

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

    // 質問送信者のアバター（自分が作成した質問 → 自分のプロフィール、受信した質問 → 相手の絵文字）
    @ViewBuilder
    private func avatar(for session: ChatSession) -> some View {
        if chatStore.isOwn(session) {
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
        } else {
            let friend = session.creatorUID.flatMap { uid in friendStore.friends.first { $0.firebaseUID == uid } }
            UserAvatarView(emoji: friend?.emoji ?? "👤", photoURL: friend?.photoURL, size: 44)
        }
    }
}

#Preview {
    ChatListView()
        .environmentObject(ChatStore())
        .environmentObject(FriendStore())
        .environmentObject(ProfileStore())
}

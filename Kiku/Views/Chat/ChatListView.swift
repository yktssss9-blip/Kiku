import SwiftUI

struct ChatListView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var friendStore: FriendStore

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

    private var sessionList: some View {
        List {
            ForEach(chatStore.sessions.sorted { $0.unlockedAt > $1.unlockedAt }) { session in
                let friend = friendStore.friend(for: session.memberId)
                NavigationLink(destination: ChatView(session: session, friend: friend)) {
                    sessionRow(session: session, friend: friend)
                }
            }
        }
    }

    private func sessionRow(session: ChatSession, friend: Friend?) -> some View {
        HStack(spacing: 12) {
            Text(friend?.emoji ?? "👤")
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(friend?.name ?? "メンバー")
                    .font(.headline)

                if let last = session.messages.last {
                    Text(last.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("「\(session.questionText)」への回答で開放")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let last = session.messages.last {
                Text(last.sentAt.formatted(.dateTime.hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ChatListView()
        .environmentObject(ChatStore())
        .environmentObject(FriendStore())
}

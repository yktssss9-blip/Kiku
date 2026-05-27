import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("ホーム", systemImage: "house.fill")
                }

            ChatListView()
                .tabItem {
                    Label("チャット", systemImage: "bubble.left.and.bubble.right.fill")
                }

            MemberListView()
                .tabItem {
                    Label("ランキング", systemImage: "crown.fill")
                }

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
    }
}

// MARK: - GroupListView

struct GroupListView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var statusStore: StatusStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var isShowingCreateSheet    = false
    @State private var isShowingStatusPost     = false
    @State private var isShowingBroadcast      = false

    var body: some View {
        NavigationStack {
            List {
                // ステータスバナー
                Section {
                    StatusBannerRow(
                        isShowingStatusPost: $isShowingStatusPost
                    )
                }

                // 全体送信ボタン
                Section {
                    Button {
                        isShowingBroadcast = true
                    } label: {
                        Label("全体に質問を送る", systemImage: "person.2.wave.2.fill")
                            .foregroundStyle(.blue)
                    }
                }

                // グループ一覧
                Section("グループ") {
                    if groupStore.groups.isEmpty {
                        Text("グループがありません\n＋ボタンから作成してください")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(groupStore.groups.sorted(by: { $0.createdAt > $1.createdAt })) { group in
                            NavigationLink(destination: GroupDetailView(group: group)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name).font(.headline)
                                    Text("\(group.memberIds.count)人").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete { groupStore.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("きく")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isShowingCreateSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingCreateSheet) { GroupCreateView() }
            .sheet(isPresented: $isShowingStatusPost)   { StatusPostView() }
            .sheet(isPresented: $isShowingBroadcast)    { BroadcastQuestionView() }
        }
    }
}

// MARK: - StatusBannerRow

struct StatusBannerRow: View {
    @EnvironmentObject private var statusStore: StatusStore
    @EnvironmentObject private var profileStore: ProfileStore
    @Binding var isShowingStatusPost: Bool

    var body: some View {
        Button {
            isShowingStatusPost = true
        } label: {
            HStack(spacing: 12) {
                Text(profileStore.emoji)
                    .font(.system(size: 36))

                if let status = statusStore.active {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(status.emoji)
                            Text(status.text)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        Text("残り \(remainingText(expiresAt: status.expiresAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("ステータスを投稿する")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func remainingText(expiresAt: Date) -> String {
        let diff = expiresAt.timeIntervalSinceNow
        if diff <= 0 { return "期限切れ" }
        let hours = Int(diff / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 { return "\(hours)時間\(minutes)分" }
        return "\(minutes)分"
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @State private var isEditingProfile = false

    var body: some View {
        NavigationStack {
            List {
                // プロフィールカード
                Section {
                    Button {
                        isEditingProfile = true
                    } label: {
                        HStack(spacing: 16) {
                            // アバター
                            profileAvatar
                                .frame(width: 60, height: 60)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(profileStore.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("プロフィールを編集")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                // アプリ情報
                Section("アプリ情報") {
                    LabeledContent("バージョン", value: "1.0.0")
                    LabeledContent("ビルド", value: "MVP")
                }
            }
            .navigationTitle("設定")
            .sheet(isPresented: $isEditingProfile) {
                ProfileSettingsView()
                    .environmentObject(profileStore)
            }
        }
    }

    private var profileAvatar: some View {
        Group {
            if let image = profileStore.profileImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
            } else {
                Text(profileStore.emoji)
                    .font(.system(size: 32))
                    .frame(width: 60, height: 60)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(Circle())
            }
        }
    }
}

// NOTE: Canvas preview does not support embedded Widget Extensions.
// Use ▶️ (Run on Simulator) to test the full app including Live Activities.
// Individual view previews (MemberListView, ProfileSetupView, etc.) still work.
#Preview("グループ一覧") {
    GroupListView()
        .environmentObject(GroupStore())
        .environmentObject(FriendStore())
        .environmentObject(StatusStore())
        .environmentObject(ProfileStore())
        .environmentObject(QuestionStore())
        .environmentObject(ChatStore())
}

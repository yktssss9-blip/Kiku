import SwiftUI
import UserNotifications
import ActivityKit

struct ContentView: View {
    @AppStorage("kiku.isDark") private var isDark: Bool = true

    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var profileStore:  ProfileStore
    @EnvironmentObject private var chatStore:     ChatStore

    /// myId 宛の未回答（pending）質問数
    private var pendingNotificationCount: Int {
        let myId = profileStore.myId
        var count = 0
        for question in questionStore.questions {
            for answer in question.answers where answer.value == "pending" && answer.memberId == myId {
                count += 1
            }
        }
        return count
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("ホーム", systemImage: "house.fill")
                }

            NotificationInboxView()
                .tabItem {
                    Label("通知", systemImage: "bell.fill")
                }
                .badge(pendingNotificationCount)

            ChatListView()
                .tabItem {
                    Label("チャット", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .badge(chatStore.totalUnread)

            MemberListView()
                .tabItem {
                    Label("ランキング", systemImage: "crown.fill")
                }

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
        .preferredColorScheme(isDark ? .dark : .light)
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
    @EnvironmentObject private var pointStore: PointStore
    @AppStorage("kiku.isDark") private var isDark: Bool = true
    @State private var isEditingProfile = false
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var liveActivityEnabled: Bool = true
    @State private var isShowingResetAlert = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

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

                // 外観
                Section("外観") {
                    Toggle("ダークモード", isOn: $isDark)
                }

                // 通知
                Section("通知") {
                    // 通知の許可
                    HStack {
                        Label("通知の許可", systemImage: "bell")
                        Spacer()
                        statusBadge(text: notifStatusText, color: notifStatusColor)
                    }

                    // Live Activity
                    HStack {
                        Label("Live Activity", systemImage: "circle.dotted")
                        Spacer()
                        statusBadge(
                            text:  liveActivityEnabled ? "有効" : "無効",
                            color: liveActivityEnabled ? .green : .secondary
                        )
                    }

                    // 設定アプリへのリンク
                    Button {
                        openNotificationSettings()
                    } label: {
                        Label("iOSの通知設定を開く", systemImage: "arrow.up.right.square")
                            .foregroundStyle(.blue)
                    }
                }

                // データ管理
                Section("データ管理") {
                    Button(role: .destructive) {
                        isShowingResetAlert = true
                    } label: {
                        Label("ポイント履歴をリセット", systemImage: "trash")
                    }
                }

                // アプリ情報
                Section("アプリ情報") {
                    LabeledContent("バージョン", value: appVersion)
                    LabeledContent("ビルド", value: buildNumber)
                }
            }
            .navigationTitle("設定")
            .alert("ポイント履歴をリセット", isPresented: $isShowingResetAlert) {
                Button("リセット", role: .destructive) {
                    pointStore.reset()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("リセットすると全員のポイント履歴が消えます。この操作は元に戻せません。")
            }
            .sheet(isPresented: $isEditingProfile) {
                ProfileSettingsView()
                    .environmentObject(profileStore)
            }
            .onAppear { loadNotificationStatus() }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willEnterForegroundNotification
                )
            ) { _ in
                loadNotificationStatus()
            }
        }
    }

    // MARK: - Notification Status

    private var notifStatusText: String {
        switch notifStatus {
        case .authorized, .provisional, .ephemeral: return "許可済み"
        case .denied:                                return "未許可"
        case .notDetermined:                         return "未設定"
        @unknown default:                            return "不明"
        }
    }

    private var notifStatusColor: Color {
        switch notifStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied:                               return .red
        default:                                    return .secondary
        }
    }

    private func loadNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notifStatus = settings.authorizationStatus
            }
        }
        liveActivityEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Status Badge

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
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

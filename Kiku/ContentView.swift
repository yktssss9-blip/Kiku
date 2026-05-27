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

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var pointStore: PointStore
    @AppStorage("kiku.isDark") private var isDark: Bool = true
    @State private var isEditingProfile = false
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var liveActivityEnabled: Bool = true
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

                // アプリ情報
                Section("アプリ情報") {
                    LabeledContent("バージョン", value: appVersion)
                    LabeledContent("ビルド", value: buildNumber)
                }
            }
            .navigationTitle("設定")
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


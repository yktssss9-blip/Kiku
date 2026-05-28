import SwiftUI
import UserNotifications
import ActivityKit
import StoreKit
import MessageUI

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
    @EnvironmentObject private var friendStore: FriendStore
    @AppStorage("kiku.isDark") private var isDark: Bool = true
    @State private var isEditingProfile = false
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var liveActivityEnabled: Bool = true
    @State private var isFriendsExpanded = false
    @State private var isAddingFriend = false
    @State private var friendToDelete: Friend? = nil
    @State private var showDeleteFriendAlert = false
    @State private var friendToBlock: Friend? = nil
    @State private var showBlockFriendAlert = false
    @State private var showMailCompose = false
    @State private var showMailUnavailableAlert = false
    @Environment(\.requestReview) private var requestReview

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

                // 友達
                Section {
                    // セクションヘッダー（トグル）
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isFriendsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 20)

                            Text("友達")
                                .font(.body)
                                .foregroundStyle(.primary)

                            if !friendStore.friends.isEmpty {
                                Text("\(friendStore.friends.count)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            Spacer()

                            Button {
                                isAddingFriend = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.blue)
                                    .padding(6)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isFriendsExpanded ? 0 : -90))
                                .padding(.leading, 4)
                        }
                    }
                    .buttonStyle(.plain)

                    // 友達一覧
                    if isFriendsExpanded {
                        if friendStore.friends.isEmpty {
                            Text("まだ友達がいません")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(friendStore.friends) { friend in
                                let blocked = friendStore.isBlocked(friend.id)
                                HStack(spacing: 12) {
                                    Text(friend.emoji)
                                        .font(.title3)
                                        .frame(width: 36, height: 36)
                                        .background(Color(UIColor.tertiarySystemBackground))
                                        .clipShape(Circle())
                                        .opacity(blocked ? 0.4 : 1)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.name)
                                            .font(.body)
                                            .foregroundStyle(blocked ? .secondary : .primary)
                                        if blocked {
                                            Text("ブロック中")
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.red.opacity(0.8))
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        friendToDelete = friend
                                        showDeleteFriendAlert = true
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }

                                    Button {
                                        friendToBlock = friend
                                        showBlockFriendAlert = true
                                    } label: {
                                        Label(
                                            blocked ? "解除" : "ブロック",
                                            systemImage: blocked ? "person.fill.checkmark" : "slash.circle"
                                        )
                                    }
                                    .tint(blocked ? .green : .orange)
                                }
                                .contextMenu {
                                    Button {
                                        friendToBlock = friend
                                        showBlockFriendAlert = true
                                    } label: {
                                        Label(
                                            blocked ? "ブロックを解除" : "ブロック",
                                            systemImage: blocked ? "person.fill.checkmark" : "slash.circle"
                                        )
                                    }
                                    Button(role: .destructive) {
                                        friendToDelete = friend
                                        showDeleteFriendAlert = true
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }

                // Stop Time
                Section {
                    Toggle(isOn: Binding(
                        get: { profileStore.isStopTimeActive },
                        set: { profileStore.isStopTimeActive = $0 }
                    )) {
                        Label("Stop Time", systemImage: "pause.circle.fill")
                    }
                    .tint(.orange)
                    if profileStore.isStopTimeActive {
                        Text("Stop Time 中は、質問の送信先に選ばれたときに相手に通知されます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Stop Time")
                } footer: {
                    Text("返信できないときにオンにすると、相手が質問を送ろうとした際に Stop Time 中であることが表示されます。")
                }

                // 外観
                Section("外観") {
                    Toggle("ダークモード", isOn: $isDark)
                }

                // 通知
                Section("通知") {
                    HStack {
                        Label("通知の許可", systemImage: "bell")
                        Spacer()
                        statusBadge(text: notifStatusText, color: notifStatusColor)
                    }

                    HStack {
                        Label("Live Activity", systemImage: "circle.dotted")
                        Spacer()
                        statusBadge(
                            text:  liveActivityEnabled ? "有効" : "無効",
                            color: liveActivityEnabled ? .green : .secondary
                        )
                    }

                    Button {
                        openNotificationSettings()
                    } label: {
                        Label("iOSの通知設定を開く", systemImage: "arrow.up.right.square")
                            .foregroundStyle(.blue)
                    }
                }

                // サポート
                Section("サポート") {
                    Button {
                        requestReview()
                    } label: {
                        Label("App Store でレビューを書く", systemImage: "star.fill")
                            .foregroundStyle(.orange)
                    }

                    Button {
                        if MFMailComposeViewController.canSendMail() {
                            showMailCompose = true
                        } else {
                            showMailUnavailableAlert = true
                        }
                    } label: {
                        Label("フィードバックを送る", systemImage: "envelope.fill")
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
            .sheet(isPresented: $isAddingFriend) {
                MemberAddView { newFriend in
                    friendStore.add(newFriend)
                }
            }
            .alert("友達を削除しますか？", isPresented: $showDeleteFriendAlert, presenting: friendToDelete) { friend in
                Button("削除", role: .destructive) {
                    friendStore.delete(id: friend.id)
                    friendToDelete = nil
                }
                Button("キャンセル", role: .cancel) {
                    friendToDelete = nil
                }
            } message: { friend in
                Text("「\(friend.name)」を友達から削除します。この操作は元に戻せません。")
            }
            .alert(
                friendToBlock.map { friendStore.isBlocked($0.id) ? "ブロックを解除しますか？" : "ブロックしますか？" } ?? "",
                isPresented: $showBlockFriendAlert,
                presenting: friendToBlock
            ) { friend in
                let blocked = friendStore.isBlocked(friend.id)
                Button(blocked ? "解除する" : "ブロックする", role: blocked ? .cancel : .destructive) {
                    if blocked {
                        friendStore.unblock(friend.id)
                    } else {
                        friendStore.block(friend.id)
                    }
                    friendToBlock = nil
                }
                Button("キャンセル", role: .cancel) {
                    friendToBlock = nil
                }
            } message: { friend in
                let blocked = friendStore.isBlocked(friend.id)
                Text(blocked
                    ? "「\(friend.name)」のブロックを解除します。"
                    : "「\(friend.name)」をブロックします。グループや質問の対象から除外されます。"
                )
            }
            .sheet(isPresented: $showMailCompose) {
                MailComposeView(
                    recipient: "sykt.feedback@gmail.com",
                    subject: "きく アプリへのフィードバック"
                )
            }
            .alert("メールを送信できません", isPresented: $showMailUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("このデバイスにメールアカウントが設定されていません。「設定」アプリからメールアカウントを追加してください。")
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

// MARK: - MailComposeView

struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
        }
    }
}


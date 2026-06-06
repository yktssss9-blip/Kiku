import SwiftUI
import UserNotifications
import ActivityKit
import StoreKit
import MessageUI

struct ContentView: View {
    @AppStorage("kiku.isDark") private var isDark: Bool = true

    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var profileStore:  ProfileStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var groupStore:    GroupStore
    @EnvironmentObject private var chatStore:     ChatStore
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @EnvironmentObject private var templateStore: TemplateStore

    /// myId 宛の未回答（pending）質問数
    var pendingNotificationCount: Int {
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
            SendTabView()
                .tabItem {
                    Label("送る", systemImage: "paperplane.fill")
                }
                .environmentObject(questionStore)
                .environmentObject(friendStore)
                .environmentObject(groupStore)
                .environmentObject(profileStore)
                .environmentObject(purchaseStore)
                .environmentObject(templateStore)

            HomeView()
                .tabItem {
                    Label("フィード", systemImage: "list.bullet")
                }

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
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @AppStorage("kiku.isDark") private var isDark: Bool = true
    @State private var isEditingProfile = false
    @State private var showPaywall = false
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
                // プロフィールカード（社員証）
                Section {
                    VStack(spacing: 10) {
                        ProfileIDCard(
                            name:         profileStore.name,
                            emoji:        profileStore.emoji,
                            profileImage: profileStore.profileImage,
                            username:     profileStore.username,
                            rank:         myRankInfo.rank,
                            outOf:        myRankInfo.outOf,
                            avgSpeed:     pointStore.averageSpeed(for: profileStore.myId),
                            answerCount:  pointStore.history(for: profileStore.myId).count
                        )
                        Button {
                            isEditingProfile = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "pencil")
                                Text("プロフィールを編集")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                // Proプラン
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 1.0, green: 0.75, blue: 0.0),
                                                     Color(red: 1.0, green: 0.55, blue: 0.0)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 36, height: 36)
                                Text("👑")
                                    .font(.system(size: 18))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(purchaseStore.isPro ? "Shigodeki Pro" : "Proプランへアップグレード")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(purchaseStore.isPro ? "ご利用中です" : "すべての機能をフル活用しよう")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if purchaseStore.isPro {
                                Text("利用中")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange)
                                    .clipShape(Capsule())
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
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
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(purchaseStore)
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

    private var myRankInfo: (rank: Int, outOf: Int) {
        let myId   = profileStore.myId
        let allIds = [myId] + friendStore.friends.map(\.id)
        let sorted = allIds.sorted {
            (pointStore.averageSpeed(for: $0) ?? .infinity) <
            (pointStore.averageSpeed(for: $1) ?? .infinity)
        }
        let rank = (sorted.firstIndex(of: myId) ?? 0) + 1
        return (rank, allIds.count)
    }
}

// MARK: - ProfileIDCard

private struct ProfileIDCard: View {
    let name:         String
    let emoji:        String
    let profileImage: Image?
    let username:     String
    let rank:         Int
    let outOf:        Int
    let avgSpeed:     Double?
    let answerCount:  Int

    private var title: PointTitle { PointTitle(rank: rank, outOf: outOf) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(cardGradient)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

            VStack(spacing: 0) {
                // ヘッダー
                HStack {
                    Text("🏢 シゴデキ株式会社")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    rankBadgeView
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // メインコンテンツ
                HStack(spacing: 14) {
                    avatarCircle
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(name.isEmpty ? "名前未設定" : name)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(title.display)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.2))
                            .clipShape(Capsule())

                        if !username.isEmpty {
                            Text("@\(username)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)

                // 区切り線
                Rectangle()
                    .fill(.white.opacity(0.2))
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                // 統計行
                HStack(spacing: 0) {
                    statCell(label: "順位",   value: "\(rank)位")
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 28)
                    statCell(label: "平均速度", value: avgSpeed.map { String(format: "%.0f秒", $0) } ?? "–")
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 28)
                    statCell(label: "回答数",  value: "\(answerCount)件")
                }
                .padding(.vertical, 12)
            }
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline).fontWeight(.bold).foregroundStyle(.white)
            Text(label)
                .font(.caption2).foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
    }

    private var rankBadgeView: some View {
        Group {
            switch rank {
            case 1: Text("🥇").font(.title3)
            case 2: Text("🥈").font(.title3)
            case 3: Text("🥉").font(.title3)
            default:
                Text("\(rank)位")
                    .font(.caption).fontWeight(.bold).foregroundStyle(.white)
            }
        }
    }

    private var avatarCircle: some View {
        Group {
            if let image = profileImage {
                image
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 2))
            } else {
                Text(emoji)
                    .font(.system(size: 38))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.15))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 2))
            }
        }
    }

    private var cardGradient: LinearGradient {
        let colors: [Color]
        switch title.color {
        case "purple": colors = [.purple,                                    .indigo]
        case "yellow": colors = [Color(red: 0.75, green: 0.55, blue: 0.0),  .orange]
        case "orange": colors = [.orange,                                    Color(red: 0.8, green: 0.3, blue: 0.1)]
        case "blue":   colors = [.blue,                                      .cyan.opacity(0.85)]
        default:       colors = [Color(UIColor.systemGray),                  Color(UIColor.systemGray2)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
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


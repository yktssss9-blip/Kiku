import SwiftUI
import UserNotifications
import Combine
import ActivityKit
import FirebaseCore
import FirebaseMessaging
import FirebaseFirestore
import FirebaseAuth
import RevenueCat

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        Purchases.configure(withAPIKey: "test_uTNfxnEanvlJHSWLXNADxMGrKnZ")
        return true
    }

    // APNsトークンをFirebase Messagingに渡す
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // FCMトークンが更新されたらFirestoreに保存
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken,
              let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid)
            .setData(["fcmToken": token], merge: true)
        print("[FCM] トークン保存: \(token.prefix(20))...")
    }
}

@main
struct KikuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authStore     = AuthStore()
    @StateObject private var profileStore  = ProfileStore()
    @StateObject private var friendStore   = FriendStore()
    @StateObject private var groupStore    = GroupStore()
    @StateObject private var questionStore = QuestionStore()
    @StateObject private var statusStore   = StatusStore()
    @StateObject private var chatStore     = ChatStore()
    @StateObject private var pointStore    = PointStore()
    @StateObject private var templateStore = TemplateStore()
    @StateObject private var purchaseStore = PurchaseStore()

    @State private var answerTarget: AnswerTarget? = nil
    @State private var pendingInviteURL: URL? = nil
    @State private var showLiveActivityDisabledAlert = false

    var body: some Scene {
        WindowGroup {
            if authStore.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if profileStore.isSetupComplete {
                ContentView()
                    .environmentObject(authStore)
                    .environmentObject(profileStore)
                    .environmentObject(friendStore)
                    .environmentObject(groupStore)
                    .environmentObject(questionStore)
                    .environmentObject(statusStore)
                    .environmentObject(chatStore)
                    .environmentObject(pointStore)
                    .environmentObject(templateStore)
                    .environmentObject(purchaseStore)
                    .onAppear {
                        requestNotificationPermission()
                        setupNotificationHandler()
                        setupChatUnlock()
                        questionStore.pointStore = pointStore
                        questionStore.senderMemberId = profileStore.myId
                        questionStore.applyPendingFromSharedStore()
                        checkLiveActivityAuthorization()
                        setupGroupDeletion()
                    }
                    // フォアグラウンド復帰時にも取り込む
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: UIApplication.willEnterForegroundNotification
                        )
                    ) { _ in
                        questionStore.applyPendingFromSharedStore()
                    }
                    // Live Activityボタン → AnswerIntent.perform() が投げる通知を受信して即反映
                    .onReceive(
                        NotificationCenter.default.publisher(for: .kikuAnswerSubmitted)
                    ) { _ in
                        questionStore.applyPendingFromSharedStore()
                    }
                    .alert("Live Activityを有効にしてください", isPresented: $showLiveActivityDisabledAlert) {
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        Button("後で", role: .cancel) {}
                    } message: {
                        Text("ロック画面・Dynamic Islandでの回答ボタンを使うには、設定 → 通知 → きく → 「Live Activity」をオンにしてください。")
                    }
                    .onOpenURL { url in
                        handleURL(url)
                    }
                    .onAppear {
                        if let url = pendingInviteURL {
                            handleURL(url)
                            pendingInviteURL = nil
                        }
                    }
                    .sheet(item: $answerTarget) { target in
                        AnswerView(
                            question:    target.question,
                            memberId:    target.memberId,
                            memberName:  target.memberName,
                            memberEmoji: target.memberEmoji,
                            isInvite:    target.isInvite
                        )
                        .environmentObject(questionStore)
                    }
            } else {
                ProfileSetupView(store: profileStore)
                    .onOpenURL { url in pendingInviteURL = url }
            }
        }
        .onChange(of: authStore.user) { _, user in
            if let user {
                profileStore.syncFromFirestore()
                questionStore.startListening(forUID: user.uid)
                chatStore.startListening(forUID: user.uid)
                pointStore.startListening(forUID: user.uid)
                templateStore.startListening(forUID: user.uid)
            } else {
                questionStore.stopListening()
                chatStore.stopListening()
                pointStore.stopListening()
                templateStore.stopListening()
            }
        }
    }

    // MARK: - URL スキーム処理

    private func handleURL(_ url: URL) {
        guard url.scheme == "kiku" else { return }
        switch url.host {
        case "answer": resolveAnswerTarget(from: url)
        case "invite": resolveInviteTarget(from: url)
        default: break
        }
    }

    private func resolveAnswerTarget(from url: URL) {
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard
            let qIdStr = params?.first(where: { $0.name == "questionId" })?.value,
            let mIdStr = params?.first(where: { $0.name == "memberId"   })?.value,
            let questionId = UUID(uuidString: qIdStr),
            let memberId   = UUID(uuidString: mIdStr),
            let question   = questionStore.questions.first(where: { $0.id == questionId })
        else { return }

        let friend = friendStore.friends.first { $0.id == memberId }
        answerTarget = AnswerTarget(
            question:    question,
            memberId:    memberId,
            memberName:  friend?.name  ?? "メンバー",
            memberEmoji: friend?.emoji ?? "👤"
        )
    }

    private func resolveInviteTarget(from url: URL) {
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard
            let qIdStr = params?.first(where: { $0.name == "qid"   })?.value,
            let token  = params?.first(where: { $0.name == "token" })?.value,
            let questionId = UUID(uuidString: qIdStr)
        else { return }

        Task { @MainActor in
            guard let question = await questionStore.fetchQuestionForInvite(questionId: questionId, token: token) else { return }
            answerTarget = AnswerTarget(
                question:    question,
                memberId:    profileStore.myId,
                memberName:  profileStore.name,
                memberEmoji: profileStore.emoji,
                isInvite:    true
            )
        }
    }

    // MARK: - 通知アクション処理（長押しボタン → 直接記録）

    private func setupNotificationHandler() {
        // 長押しボタン → 直接記録
        NotificationManager.shared.onAnswer = { questionId, memberId, value in
            DispatchQueue.main.async {
                questionStore.submit(questionId: questionId, memberId: memberId, value: value)
                Task {
                    if let q = questionStore.questions.first(where: { $0.id == questionId }) {
                        await ActivityManager.shared.update(
                            questionId: questionId,
                            summary:    q.summary()
                        )
                    }
                }
            }
        }

        // 通知本文タップ → AnswerView を開く
        NotificationManager.shared.onOpenAnswer = { questionId, memberId in
            guard let question = questionStore.questions.first(where: { $0.id == questionId }) else { return }
            let friend = friendStore.friends.first { $0.id == memberId }
            answerTarget = AnswerTarget(
                question:    question,
                memberId:    memberId,
                memberName:  friend?.name  ?? "メンバー",
                memberEmoji: friend?.emoji ?? "👤"
            )
        }
    }

    private func setupGroupDeletion() {
        groupStore.onGroupDeleted = { [weak questionStore] groupId in
            DispatchQueue.main.async {
                questionStore?.deleteQuestions(forGroupId: groupId)
            }
        }
    }

    private func setupChatUnlock() {
        questionStore.onAnswered = { questionId, memberId, questionText, answerValue in
            DispatchQueue.main.async {
                let friend = self.friendStore.friend(for: memberId)
                chatStore.unlock(
                    questionId:   questionId,
                    memberId:     memberId,
                    questionText: questionText,
                    answerValue:  answerValue,
                    friendName:   friend?.name  ?? "メンバー",
                    friendEmoji:  friend?.emoji ?? "👤"
                )
                Task {
                    await ActivityManager.shared.end(questionId: questionId, memberId: memberId)
                }
            }
        }
    }

    // MARK: - Live Activity 認証チェック

    private func checkLiveActivityAuthorization() {
        let info = ActivityAuthorizationInfo()
        if !info.areActivitiesEnabled {
            showLiveActivityDisabledAlert = true
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}

// MARK: - AnswerTarget

struct AnswerTarget: Identifiable {
    let id = UUID()
    let question: Question
    let memberId: UUID
    let memberName: String
    let memberEmoji: String
    var isInvite: Bool = false
}

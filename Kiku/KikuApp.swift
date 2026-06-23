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
        Purchases.configure(withAPIKey: "appl_bnAHfpSDLDPPThnrVzRFySqOnPQ")
        return true
    }

    static var pendingApnsDeviceToken: String?

    // APNsトークンをFirebase Messagingに渡し、Firestoreにも保存する
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        let tokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        if let uid = Auth.auth().currentUser?.uid {
            Firestore.firestore().collection("users").document(uid)
                .setData(["apnsDeviceToken": tokenHex], merge: true)
        } else {
            AppDelegate.pendingApnsDeviceToken = tokenHex
        }
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
    @StateObject private var reviewManager = ReviewManager()

    @State private var selectedTab = 0
    @State private var answerTarget: AnswerTarget? = nil
    @State private var pendingInviteURL: URL? = nil
    @State private var showLiveActivityDisabledAlert = false

    var body: some Scene {
        WindowGroup {
            if authStore.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authStore.user == nil {
                LoginView()
                    .environmentObject(authStore)
            } else if profileStore.isSetupComplete {
                ContentView(selectedTab: $selectedTab)
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
                    .environmentObject(reviewManager)
                    .onAppear {
                        requestNotificationPermission()
                        setupNotificationHandler()
                        setupChatUnlock()
                        questionStore.pointStore = pointStore
                        groupStore.friendStore = friendStore
                        questionStore.senderMemberId = profileStore.myId
                        questionStore.senderName  = profileStore.name
                        questionStore.senderEmoji = profileStore.emoji
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
                        applyPendingOpenPickers()
                        Task { await friendStore.refreshFriendProfiles() }
                        Task {
                            try? await UNUserNotificationCenter.current().setBadgeCount(chatStore.totalUnread)
                        }
                        for q in questionStore.receivedQuestions where q.summary().pending > 0 {
                            Task { @MainActor in
                                await ActivityManager.shared.update(questionId: q.id, summary: q.summary())
                            }
                        }
                    }
                    // Live Activityボタン → AnswerIntent.perform() が投げる通知を受信して即反映
                    .onReceive(
                        NotificationCenter.default.publisher(for: .kikuAnswerSubmitted)
                    ) { _ in
                        questionStore.applyPendingFromSharedStore()
                    }
                    // 星・時間ピッカーを開く通知
                    .onReceive(
                        NotificationCenter.default.publisher(for: .kikuOpenPicker)
                    ) { _ in
                        applyPendingOpenPickers()
                    }
                    // 友達申請 Live Activity ○/✕ ボタン → 即反映
                    .onReceive(
                        NotificationCenter.default.publisher(for: .kikuFriendRequestResponse)
                    ) { _ in
                        applyPendingFriendRequestResponses()
                    }
                    .alert("Live Activityを有効にしてください", isPresented: $showLiveActivityDisabledAlert) {
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        Button("後で", role: .cancel) {}
                    } message: {
                        Text("ロック画面・Dynamic Islandでの回答ボタンを使うには、設定 → 通知 → Kiku → 「Live Activity」をオンにしてください。")
                    }
                    .onOpenURL { url in
                        handleURL(url)
                    }
                    .onChange(of: chatStore.totalUnread) { _, count in
                        Task {
                            try? await UNUserNotificationCenter.current().setBadgeCount(count)
                        }
                    }
                    .onAppear {
                        applyPendingOpenPickers()
                    }
                    .onAppear {
                        if let url = pendingInviteURL {
                            handleURL(url)
                            pendingInviteURL = nil
                        }
                    }
                    .sheet(item: $answerTarget) { target in
                        AnswerView(
                            question:         target.question,
                            memberId:         target.memberId,
                            memberName:       target.memberName,
                            memberEmoji:      target.memberEmoji,
                            memberPhotoURL:   target.memberPhotoURL,
                            isInvite:         target.isInvite,
                            jumpToTimePicker: target.jumpToTimePicker
                        )
                        .environmentObject(questionStore)
                    }
                    .sheet(isPresented: $reviewManager.showPrompt) {
                        ReviewPromptView()
                            .environmentObject(reviewManager)
                    }
            } else if pendingInviteURL != nil {
                InviteSetupView(store: profileStore)
                    .onOpenURL { url in pendingInviteURL = url }
            } else {
                ProfileSetupView(store: profileStore)
                    .environmentObject(authStore)
                    .onOpenURL { url in pendingInviteURL = url }
            }
        }
        .onChange(of: authStore.user) { _, user in
            if let user {
                profileStore.syncFromFirestore()
                Task { await friendStore.refreshFriendProfiles() }
                questionStore.startListening(forUID: user.uid)
                chatStore.startListening(forUID: user.uid)
                pointStore.startListening(forUID: user.uid)
                templateStore.startListening(forUID: user.uid)
                groupStore.startListening(forUID: user.uid)
                questionStore.startListeningReceived(forUID: user.uid)
                chatStore.startListeningReceived(forUID: user.uid)
                friendStore.startListeningRequests(forUID: user.uid)
                ActivityManager.shared.observePushToStartToken()
                // didReceiveRegistrationToken はサインイン前に発火し保存に失敗することがあるため、サインイン後に再取得して保存する
                Messaging.messaging().token { token, error in
                    guard let token, error == nil else { return }
                    Firestore.firestore().collection("users").document(user.uid)
                        .setData(["fcmToken": token], merge: true)
                }
                // APNs デバイストークンがサインイン前に届いていた場合は保存する
                if let apnsToken = AppDelegate.pendingApnsDeviceToken {
                    Firestore.firestore().collection("users").document(user.uid)
                        .setData(["apnsDeviceToken": apnsToken], merge: true)
                    AppDelegate.pendingApnsDeviceToken = nil
                }
            } else {
                questionStore.stopListening()
                chatStore.stopListening()
                pointStore.stopListening()
                templateStore.stopListening()
                groupStore.stopListening()
                questionStore.stopListeningReceived()
                chatStore.stopListeningReceived()
                friendStore.stopListeningRequests()
            }
        }
    }

    // MARK: - ピッカー遷移（Live Activity 星・時間ボタン）

    private func applyPendingOpenPickers() {
        let defaults = UserDefaults(suiteName: "group.com.yukichi.kiku")
        guard let allKeys = defaults?.dictionaryRepresentation().keys else { return }
        for key in allKeys where key.hasPrefix("open_picker.") {
            // "open_picker.{questionId}.{memberId}" を分解
            // UUID には . が含まれないので先頭プレフィクスを除いて split
            let suffix = String(key.dropFirst("open_picker.".count))
            let dotIdx = suffix.lastIndex(of: ".") ?? suffix.endIndex
            let qIdStr = String(suffix[suffix.startIndex..<dotIdx])
            let mIdStr = dotIdx < suffix.endIndex ? String(suffix[suffix.index(after: dotIdx)...]) : ""
            guard
                let questionId = UUID(uuidString: qIdStr),
                let memberId   = UUID(uuidString: mIdStr)
            else { continue }

            let pickerType = defaults?.string(forKey: key) ?? ""
            defaults?.removeObject(forKey: key)

            let question = questionStore.questions.first(where: { $0.id == questionId })
                        ?? questionStore.receivedQuestions.first(where: { $0.id == questionId })
            guard let question else { continue }

            let isOwn  = questionStore.questions.contains(where: { $0.id == questionId })
            let friend = friendStore.friends.first { $0.id == memberId }
            answerTarget = AnswerTarget(
                question:         question,
                memberId:         memberId,
                memberName:       isOwn ? (friend?.name  ?? "メンバー") : profileStore.name,
                memberEmoji:      isOwn ? (friend?.emoji ?? "👤")       : profileStore.emoji,
                memberPhotoURL:   isOwn ? friend?.photoURL               : profileStore.photoURL,
                jumpToTimePicker: pickerType == "open_time"
            )
        }
    }

    // MARK: - 友達申請 Live Activity レスポンス処理

    private func applyPendingFriendRequestResponses() {
        let defaults = UserDefaults(suiteName: "group.com.yukichi.kiku")
        guard let allKeys = defaults?.dictionaryRepresentation().keys else { return }
        for key in allKeys where key.hasPrefix("friendRequest.response.") {
            let requestId = String(key.dropFirst("friendRequest.response.".count))
            let accept = defaults?.bool(forKey: key) ?? false
            defaults?.removeObject(forKey: key)
            guard let req = friendStore.pendingRequests.first(where: { $0.id == requestId }) else { continue }
            Task {
                if accept {
                    await friendStore.acceptFriendRequest(
                        requestId:    req.id,
                        fromUID:      req.fromUID,
                        fromName:     req.fromName,
                        fromEmoji:    req.fromEmoji,
                        fromPhotoURL: req.fromPhotoURL,
                        fromUsername: req.fromUsername
                    )
                } else {
                    await friendStore.declineFriendRequest(requestId: req.id)
                }
                await ActivityManager.shared.endFriendRequest(requestId: requestId)
            }
        }
    }

    // MARK: - URL スキーム処理

    private func handleURL(_ url: URL) {
        if url.scheme == "kiku" {
            switch url.host {
            case "answer": resolveAnswerTarget(from: url)
            case "invite": resolveInviteTarget(from: url)
            default: break
            }
        } else if url.host == "shigodeki-8e49a.web.app" {
            resolveWebInviteTarget(from: url)
        }
    }

    private func resolveWebInviteTarget(from url: URL) {
        let parts = url.pathComponents // ["", "q", "{questionId}"]
        guard parts.count >= 3, parts[1] == "q",
              let questionId = UUID(uuidString: parts[2]),
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "token" })?.value
        else { return }
        Task { @MainActor in
            guard let question = await questionStore.fetchQuestionForInvite(questionId: questionId, token: token) else { return }
            answerTarget = AnswerTarget(
                question:       question,
                memberId:       profileStore.myId,
                memberName:     profileStore.name,
                memberEmoji:    profileStore.emoji,
                memberPhotoURL: profileStore.photoURL,
                isInvite:       true
            )
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
            question:       question,
            memberId:       memberId,
            memberName:     friend?.name  ?? "メンバー",
            memberEmoji:    friend?.emoji ?? "👤",
            memberPhotoURL: friend?.photoURL
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
                question:       question,
                memberId:       profileStore.myId,
                memberName:     profileStore.name,
                memberEmoji:    profileStore.emoji,
                memberPhotoURL: profileStore.photoURL,
                isInvite:       true
            )
        }
    }

    // MARK: - 通知アクション処理（長押しボタン → 直接記録）

    private func setupNotificationHandler() {
        // 友達申請が届いたら Live Activity を起動
        friendStore.onReceivedRequest = { request in
            ActivityManager.shared.startFriendRequest(
                requestId: request.id,
                fromUID:   request.fromUID,
                fromName:  request.fromName,
                fromEmoji: request.fromEmoji
            )
        }

        NotificationManager.shared.onFriendRequestAccept = { requestId, fromUID, fromName, fromEmoji, fromPhotoURL in
            Task {
                await friendStore.acceptFriendRequest(
                    requestId:    requestId,
                    fromUID:      fromUID,
                    fromName:     fromName,
                    fromEmoji:    fromEmoji,
                    fromPhotoURL: fromPhotoURL
                )
                await ActivityManager.shared.endFriendRequest(requestId: requestId)
            }
        }
        NotificationManager.shared.onFriendRequestDecline = { requestId in
            Task {
                await friendStore.declineFriendRequest(requestId: requestId)
                await ActivityManager.shared.endFriendRequest(requestId: requestId)
            }
        }

        // チャット通知タップ → チャットタブに切り替えて該当チャットを開く
        NotificationManager.shared.onOpenChat = { questionId in
            DispatchQueue.main.async {
                selectedTab = 2
                NotificationCenter.default.post(
                    name: .kikuOpenChat,
                    object: nil,
                    userInfo: ["questionId": questionId]
                )
            }
        }

        // 長押しボタン → 直接記録（自分が送った質問 / 自分宛に届いた質問の両方に対応）
        NotificationManager.shared.onAnswer = { questionId, memberId, value in
            DispatchQueue.main.async {
                if questionStore.questions.contains(where: { $0.id == questionId }) {
                    questionStore.submit(questionId: questionId, memberId: memberId, value: value)
                } else {
                    questionStore.submitReceived(questionId: questionId, memberId: memberId, value: value)
                }
                Task {
                    if let q = questionStore.questions.first(where: { $0.id == questionId })
                        ?? questionStore.receivedQuestions.first(where: { $0.id == questionId }) {
                        await ActivityManager.shared.update(
                            questionId: questionId,
                            summary:    q.summary()
                        )
                    }
                }
            }
        }

        // 他ユーザーから届いた質問を検知 → Live Activity + ローカル通知
        questionStore.onReceivedQuestion = { question, memberId in
            let senderFriend = friendStore.friends.first { $0.firebaseUID == question.createdBy }
            Task { @MainActor in
                ActivityManager.shared.start(
                    question:   question,
                    memberId:   memberId,
                    memberName: profileStore.name
                )
                NotificationManager.shared.scheduleQuestion(
                    questionId:          question.id,
                    memberId:            memberId,
                    memberName:          profileStore.name,
                    memberEmoji:         profileStore.emoji,
                    questionText:        question.text,
                    choices:             question.answerChoices,
                    overrideSenderName:  senderFriend?.name  ?? "Kiku",
                    overrideSenderEmoji: senderFriend?.emoji ?? "👤"
                )
            }
        }

        // 通知本文タップ → AnswerView を開く（自分が送った質問 / 自分宛に届いた質問の両方に対応）
        NotificationManager.shared.onOpenAnswer = { questionId, memberId in
            if let question = questionStore.questions.first(where: { $0.id == questionId }) {
                let friend = friendStore.friends.first { $0.id == memberId }
                answerTarget = AnswerTarget(
                    question:       question,
                    memberId:       memberId,
                    memberName:     friend?.name  ?? "メンバー",
                    memberEmoji:    friend?.emoji ?? "👤",
                    memberPhotoURL: friend?.photoURL
                )
            } else if let question = questionStore.receivedQuestions.first(where: { $0.id == questionId }) {
                // 受信した質問では memberId は自分自身を指す
                answerTarget = AnswerTarget(
                    question:       question,
                    memberId:       memberId,
                    memberName:     profileStore.name,
                    memberEmoji:    profileStore.emoji,
                    memberPhotoURL: profileStore.photoURL
                )
            }
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
                guard let myUID = authStore.user?.uid else { return }

                let ownerUID: String
                let participantUID: String?
                let friendName: String
                let friendEmoji: String

                if let received = questionStore.receivedQuestions.first(where: { $0.id == questionId }) {
                    // 受信した質問に自分が回答した → チャットの持ち主は質問の作成者
                    ownerUID       = received.createdBy ?? myUID
                    participantUID = myUID
                    friendName     = profileStore.name
                    friendEmoji    = profileStore.emoji
                } else {
                    // 自分が送った質問に友達が回答した → チャットの持ち主は自分
                    let friend = self.friendStore.friend(for: memberId)
                    ownerUID       = myUID
                    participantUID = (friend?.firebaseUID.isEmpty == false) ? friend?.firebaseUID : nil
                    friendName     = friend?.name  ?? "メンバー"
                    friendEmoji    = friend?.emoji ?? "👤"
                }

                chatStore.unlock(
                    questionId:     questionId,
                    memberId:       memberId,
                    questionText:   questionText,
                    answerValue:    answerValue,
                    friendName:     friendName,
                    friendEmoji:    friendEmoji,
                    ownerUID:       ownerUID,
                    participantUID: participantUID
                )
                // 星評価は AnswerView 内でレビューボタンを表示するため除外
                if !answerValue.hasPrefix("star:") {
                    reviewManager.onAnswered()
                }
                Task {
                    await ActivityManager.shared.end(questionId: questionId, memberId: memberId)
                }
            }
        }

        questionStore.onAnswerEdited = { questionId, memberId, _, _, newValue in
            DispatchQueue.main.async {
                pointStore.invalidate(questionId: questionId, memberId: memberId)
                chatStore.updateAnswerMessage(questionId: questionId, memberId: memberId, newAnswerValue: newValue)
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
            NotificationManager.shared.registerFriendRequestCategory()
            NotificationManager.shared.registerChatCategory()
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
    var memberPhotoURL: String? = nil
    var isInvite: Bool = false
    var jumpToTimePicker: Bool = false
}
